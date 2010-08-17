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

    // Print some OCDB stuff
    entry->PrintMetaData();

  } // end if fApplyEff

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
  fListHistos = new TList();
  fHistoEff = new TH1I("hEff", "Computed track weights", 200, 0.0, 1.2);
  fHistoDev = new TH1I("hDev", "Deviations (n. local boards)", 6, -3., 3.);
  fListHistos->Add(fHistoEff);
  fListHistos->Add(fHistoDev);

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

      // Here goes the code that selects the track...
      Bool_t keep = kFALSE;

      Int_t loBo1 = esdMt->LoCircuit();
      Int_t loBo2;
      Int_t loBoDev;

      if ((fApplyEff) && (loBo1 != 0)) {

        // Calculate the deviation in terms of number of sw local boards
        loBoDev = (esdMt->LoDev() + esdMt->LoStripX() - 15)/32;
        fHistoDev->Fill(loBoDev);

        // Second local board touched
        loBo2 = loBo1 + loBoDev;

        Float_t mtrEff;
        Float_t r[4];

        // Get R values from OCDB (bending plane and nonbending use the same
        // vals)
        for (Int_t i=0; i<4; i++) {
          Int_t detElemId = 1000+100*(i+1);
          if (i < 2) {
            // Efficiencies on M11, M12
            r[i] = fTrigChEff->GetCellEfficiency(detElemId, loBo1,
              AliMUONTriggerEfficiencyCells::kBendingEff);
          }
          else {
            // Efficiencies on M21, M22
            r[i] = fTrigChEff->GetCellEfficiency(detElemId, loBo2,
              AliMUONTriggerEfficiencyCells::kBendingEff);
          }
        }

        mtrEff  =   r[0]    *   r[1]    *   r[2]    *   r[3]    +
                  (1.-r[0]) *   r[1]    *   r[2]    *   r[3]    +
                    r[0]    * (1.-r[1]) *   r[2]    *   r[3]    +
                    r[0]    *   r[1]    * (1.-r[2]) *   r[3]    +
                    r[0]    *   r[1]    *   r[2]    * (1.-r[3]);

        fHistoEff->Fill(mtrEff);

        // Initialize properly the gRandom variable for parallel processing!
        keep = (gRandom->Rndm() < mtrEff);

        // Print status
        /*AliInfo(Form("EVT %d TRK %d ---> LO1 %d LO2 %d ---> EFF %.2f ---> %s",
          evNumForEsdAndMc, iTrack, loBo1, loBo2, mtrEff,
          (keep ? "KEPT" : "**REJ**")
        ));*/

      }

      if (keep) {
        esdMt->SetHitsPatternInTrigCh(esdMt->GetHitsPatternInTrigCh() | 0x8000);
      }
      // ...end of the code that selects the track

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
  PostData(2, fListHistos);

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
