#include "AliAnalysisTaskAppMtrEff.h"

ClassImp(AliAnalysisTaskAppMtrEff)

////////////////////////////////////////////////////////////////////////////////
// Constructor for the analysis task. It has some optional arguments that, if
// given, make the analysis also set a flag if the event was triggered or not by
// simulating a trigger decision from the R tables in OCDB.
////////////////////////////////////////////////////////////////////////////////
AliAnalysisTaskAppMtrEff::AliAnalysisTaskAppMtrEff(
  const char *name, Bool_t applyEfficiencies, Int_t runNum,
  const char *ocdbTrigChEff) :
    AliAnalysisTask(name, name),
    fTreeMc(0x0),
    fTreeRec(0x0),
    fEventMc(0x0),
    fEventEsd(0x0),
    fApplyEff(applyEfficiencies)
{

  // Input slot #0 works with a TChain
  DefineInput(0, TChain::Class());

  // Output slots #0 and #1 write into a TNtuple container
  DefineOutput(0, TTree::Class());
  DefineOutput(1, TTree::Class());

  // Output slot #1 writes into a TList of histograms
  DefineOutput(2, TList::Class());

  // Decides if to apply or not the trigger decision
  if (fApplyEff) {

    // Sets our custom OCDB
    AliCDBManager *man = AliCDBManager::Instance();
    man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");
    if (ocdbTrigChEff) {
      man->SetSpecificStorage("MUON/Calib/TriggerEfficiency", ocdbTrigChEff);
    }
    man->SetRun(runNum);

    // Gets the object from the OCDB
    AliCDBEntry *entry = man->Get("MUON/Calib/TriggerEfficiency");
    TObject *obj = entry->GetObject();

    // Gets the class that handles the efficiencies
    fTrigChEff = new AliMUONTriggerChamberEfficiency(
      dynamic_cast<AliMUONTriggerEfficiencyCells*>(obj)
    );

  } // end if fApplyEff


  gSystem->Exit(66);
}

////////////////////////////////////////////////////////////////////////////////
// Destructor
////////////////////////////////////////////////////////////////////////////////
AliAnalysisTaskAppMtrEff::~AliAnalysisTaskAppMtrEff() {}

////////////////////////////////////////////////////////////////////////////////
// This function is called to create objects that store the output data. It is
// thus called only once when running the analysis
////////////////////////////////////////////////////////////////////////////////
void AliAnalysisTaskAppMtrEff::CreateOutputObjects() {

  // TList of histograms: we can fill it with histograms, if we want, but it is
  // empty at the moment
  fHistoList = new TList();

  // TTree for MC (generated) muons
  fTreeMc = new TTree("muGen", "Generated MC muons");
  fEventMc = 0x0;
  fTreeMc->Branch("MuonTracks", &fEventMc);

  // TTree for rec muons
  fTreeRec = new TTree("muRec", "Reconstructed muons");
  fEventEsd = 0x0;
  fTreeRec->Branch("MuonTracks", &fEventEsd);
}

////////////////////////////////////////////////////////////////////////////////
// Used to connect input data from ESD to the analysis task
////////////////////////////////////////////////////////////////////////////////
void AliAnalysisTaskAppMtrEff::ConnectInputData(Option_t *) {

  TTree* tree = dynamic_cast<TTree*>( GetInputData(0) );

  if (!tree) {
    AliError("Could not read chain from input slot 0");
    return;
  }

  // Disable all branches and enable only the needed ones
  tree->SetBranchStatus("*", kFALSE);
  tree->SetBranchStatus("MuonTracks.*", kTRUE);

  // Gets the ESD input handler
  AliESDInputHandler *esdH = dynamic_cast<AliESDInputHandler *>(
    AliAnalysisManager::GetAnalysisManager()->GetInputEventHandler()
  );

  if (esdH) {
    fCurEsdEvt = esdH->GetEvent();
    AliInfo("Accessing ESD events");
  }
  else {
    AliError("Can't access ESD events");
  }

  // Monte Carlo events are read too
  AliMCEventHandler *mcH = dynamic_cast<AliMCEventHandler *>(
    AliAnalysisManager::GetAnalysisManager()->GetMCtruthEventHandler()
  );

  if (mcH) {
    fCurMcEvt = mcH->MCEvent();
    AliInfo("Accessing Monte Carlo events");
  }
  else {
    AliError("Can't access Monte Carlo events");
  }

}

////////////////////////////////////////////////////////////////////////////////
// The main method of the analysis, executed once per event
////////////////////////////////////////////////////////////////////////////////
void AliAnalysisTaskAppMtrEff::Exec(Option_t *) {

  if (!fCurEsdEvt) {
    AliError("ESD event not available");
    return;
  }
  else if (!fCurMcEvt) {
    AliError("MC event not available");
    return;
  }

  //////////////////////////////////////////////////////////////////////////////
  // Reconstructed events
  //////////////////////////////////////////////////////////////////////////////

  AliESDInputHandler *esdH = dynamic_cast<AliESDInputHandler*>(
    AliAnalysisManager::GetAnalysisManager()->GetInputEventHandler()
  );

  // fCurEsdEvt->GetEventNumberInFile() always returns zero, why?! Looking for a
  // better way to label events
  Int_t evNumForEsdAndMc = esdH->GetReadEntry();

  Int_t nRecMuTracks = (Int_t)fCurEsdEvt->GetNumberOfMuonTracks();

  if (nRecMuTracks > 0) {

    // This instance of fEvent is for reconstructed muons
    fEventEsd = new EventEsd(
      evNumForEsdAndMc,
      (esdH->GetTree()->GetCurrentFile())->GetName()
    );

    TClonesArray *tracksArray = fEventEsd->GetTracks();
    TClonesArray &ta = *tracksArray;  // to have easier access to operator[]

    Int_t n = 0;
    for (Int_t iTrack = 0; iTrack<nRecMuTracks; iTrack++) {

      AliESDMuonTrack *esdMt = fCurEsdEvt->GetMuonTrack(iTrack);

      if (!esdMt) {
        AliError(Form("Could not receive ESD muon track %d", iTrack));
        continue;
      }

      new (ta[n++]) AliESDMuonTrack(*esdMt);

    } // track loop

    // Fill the TTrees with stuff
    fTreeRec->Fill();

  } // end of reconstructed muons processing

  //////////////////////////////////////////////////////////////////////////////
  // Monte Carlo events
  //////////////////////////////////////////////////////////////////////////////

  Int_t nMcTracks = fCurMcEvt->GetNumberOfTracks();

  if (nMcTracks > 0) {

    // This instance of fEvent is for reconstructed muons
    fEventMc = new EventMc(evNumForEsdAndMc);

    TClonesArray *tracksArray = fEventMc->GetTracks();
    TClonesArray &ta = *tracksArray;  // to have easier access to operator[]

    Int_t n = 0;
    for (Int_t iTrack=0; iTrack<nMcTracks; iTrack++) { 

      AliMCParticle *mcPart = (AliMCParticle *)(fCurMcEvt->GetTrack(iTrack));
      TParticle *tPart = mcPart->Particle();

      // Rapidity and Pt cuts (default -4<y<-2.5 and 0<pt<20)
      //if (!fCFManager->CheckParticleCuts(AliCFManager::kPartAccCuts, mcPart))
      //  continue;

      // Rapidity and Pt cuts (default -4<y<-2.5 and 0<pt<20) wo/corrfw
      Double_t rap = Rapidity(tPart->Energy(), tPart->Pz());
      Double_t pt  = tPart->Pt();
      if ((pt<0) || (pt>20) || (rap<-4) || (rap>-2.5)) continue;

      // Selection of muons (mu+ = -13, mu- = +13)
      if (TMath::Abs( mcPart->Particle()->GetPdgCode() ) == 13) {
        new (ta[n++]) TParticle(*tPart);
      }

    }
 
    if (n > 0) {
      fTreeMc->Fill();
    }
 
  } // end of monte carlo tracks selection

  //////////////////////////////////////////////////////////////////////////////
  // Post output data
  //////////////////////////////////////////////////////////////////////////////

  // Output data is posted
  PostData(0, fTreeRec);
  PostData(1, fTreeMc);
  PostData(2, fHistoList);

}      

////////////////////////////////////////////////////////////////////////////////
// Called at the end of the analysis
////////////////////////////////////////////////////////////////////////////////
void AliAnalysisTaskAppMtrEff::Terminate(Option_t *) {}

////////////////////////////////////////////////////////////////////////////////
// Rapidity from energy and Pz (static)
////////////////////////////////////////////////////////////////////////////////
Double_t AliAnalysisTaskAppMtrEff::Rapidity(Double_t e, Double_t pz) {
  Double_t rap;
  if (e != pz) {
    rap = 0.5*TMath::Log((e+pz)/(e-pz));
  }
  else {
    rap = -200;
  }
  return rap;
}
