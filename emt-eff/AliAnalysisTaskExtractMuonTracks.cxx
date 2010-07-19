#include "AliAnalysisTaskExtractMuonTracks.h"

ClassImp(AliAnalysisTaskExtractMuonTracks)

/** Constructor for the analysis task. It has some optional arguments that, if
 *  given, make the analysis also set a flag if the event was triggered or not
 *  by using a trigger decision added "a posteriori" from the R tables in OCDB.
 */
AliAnalysisTaskExtractMuonTracks::AliAnalysisTaskExtractMuonTracks(
  const char *name, Bool_t applyTriggerDecision, Int_t runNum,
  const char *ocdbSpecificStorage) :
    AliAnalysisTaskSE(name),
    fTreeOut(0),
    fEvent(0),
    fTrigDec(applyTriggerDecision),
    fRunNum(runNum),
    fOcdbSpecificStorage(ocdbSpecificStorage),
    fTrigChEff(NULL)
{
  // Input slot #0 works with a TChain
  DefineInput(0, TChain::Class());

  // Output slot #0 is already defined in Ali...SE

  // Output slot #1 writes into a TNtuple container
  DefineOutput(1, TTree::Class());

  // Output slot #2 writes into a TList of histograms
  DefineOutput(2, TList::Class());

}

/** Used to connect input data from ESD or AOD to the analysis task. It is
 *  called only once.
 */
void AliAnalysisTaskExtractMuonTracks::ConnectInputData(Option_t *opt) {

  AliAnalysisTaskSE::ConnectInputData(opt);

  if (fTrigDec) {

    // Initialize the OCDB (is it the right place to do it?!)
    AliCDBManager *man = AliCDBManager::Instance();
    man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");
    if (fOcdbSpecificStorage != NULL) {
      man->SetSpecificStorage("MUON/Calib/TriggerEfficiency",
        fOcdbSpecificStorage);
    }
    man->SetRun(fRunNum);

    AliCDBEntry *entry = man->Get("MUON/Calib/TriggerEfficiency");
    TObject *obj = entry->GetObject();

    fTrigChEff = new AliMUONTriggerChamberEfficiency(
      dynamic_cast<AliMUONTriggerEfficiencyCells*>(obj)
    );
  }


  /*
  TTree* tree = dynamic_cast<TTree*> (GetInputData(0));
  if (!tree) {
    AliError("Could not read chain from input slot 0");
  }
  else {

    // Disable all branches and enable only the needed ones; the next two lines
    // are different when data produced as AliESDEvent is read
    tree->SetBranchStatus("*", kFALSE);
    tree->SetBranchStatus("MuonTracks.*", kTRUE);


  }
  */

}

/** This function is called to create objects that store the output data. It is
 *  thus called only once when running the analysis.
 */
void AliAnalysisTaskExtractMuonTracks::UserCreateOutputObjects() {

  // Create output TTree
  fTreeOut = new TTree("muonTracks", "Muon tracks");
  fEvent = NULL;
  fTreeOut->Branch("Events", &fEvent);  // the branch "Events" holds objects of
                                        // class event

  // Output list of TH1Fs
  fHistoList = new TList();

  // Sample histogram with the Pt distribution (test)
  fHistoPt = new TH1F("histpt", "Pt distribution", 100, 0., 4.);
  fHistoPt->GetXaxis()->SetTitle("Pt [GeV/c]");
  fHistoList->Add(fHistoPt);

  /*
  fHistoTrTr = new TH1I("trtr", "trtr", 3, 0, 3);
  fHistoTrTr->GetXaxis()->SetBinLabel(1, "tracker");
  fHistoTrTr->GetXaxis()->SetBinLabel(2, "trigger");
  fHistoTrTr->GetXaxis()->SetBinLabel(3, "both");

  fHistoX1 = new TH1I("trx1", "trx1", 1000, 0, 1000);

  fHistoLo = new TH1I("lo", "lo", 234, 0.5, 234.5);

  fHistoList->Add(fHistoTrTr);
  fHistoList->Add(fHistoX1);
  fHistoList->Add(fHistoLo);
  */

  // Kinematic distributions
  /*
  fHistoTheta = new TH1F("histTheta", "#theta distribution", 1000, 0.,
    TMath::Pi());
  fHistoTheta->GetXaxis()->SetTitle("#theta [rad]");

  fHistoPhi = new TH1F("histPhi", "#varphi distribution", 1000, 0.,
    TMath::Pi());
  fHistoPhi->GetXaxis()->SetTitle("#varphi [rad]");

  fHistoP = new TH1F("histP", "Total momentum distribution", 1000, 0., 100.);
  fHistoP->GetXaxis()->SetTitle("P [GeV/c]");

  fHistoDca = new TH1F("histDca", "DCA distribution", 1000, 0., 100.);
  fHistoDca->GetXaxis()->SetTitle("DCA [cm]");

  fHistoList->Add(fHistoTheta);
  fHistoList->Add(fHistoPhi);
  fHistoList->Add(fHistoP);
  fHistoList->Add(fHistoDca);
  */

}

/** This code is the core of the analysis: it is executed once per event. At
 *  each loop, fInputEvent of type AliESDEvent points to the current event.
 */
void AliAnalysisTaskExtractMuonTracks::UserExec(Option_t *) {

  if (!fInputEvent) {
    AliError("fInputEvent not available");
    return;
  }

  AliESDEvent *esdEv = dynamic_cast<AliESDEvent *>(fInputEvent);

  Int_t nTracks = (Int_t)esdEv->GetNumberOfMuonTracks();
  if (nTracks == 0) return;

  AliESDInputHandler *esdH = dynamic_cast<AliESDInputHandler*>(
    AliAnalysisManager::GetAnalysisManager()->GetInputEventHandler()
  );

  fEvent = new Event(
    (esdH->GetTree()->GetCurrentFile())->GetName(),
    (Int_t)esdH->GetReadEntry()
  );

  TClonesArray *tracksArray = fEvent->GetTracks();  // è dentro Event
  TClonesArray &ta = *tracksArray;  // per accedere all'op. parentesi quadre
  
  Int_t n = 0;  // conta nel tclonesarray
  for (Int_t iTrack = 0; iTrack < nTracks; iTrack++) {

    AliESDMuonTrack* muonTrack = new AliESDMuonTrack(
      *( esdEv->GetMuonTrack(iTrack) )
    );

    if (!muonTrack) {
      AliError(Form("Could not receive track %d", iTrack));
      continue;
    }

    new (ta[n++]) AliESDMuonTrack(*muonTrack);

    fHistoPt->Fill( muonTrack->Pt() );

    Bool_t tri = muonTrack->ContainTriggerData();
    Bool_t tra = muonTrack->ContainTrackerData();

    /*
    if ((tri) && (tra)) {
      fHistoTrTr->Fill(2.5);
    }
    else if (tri) {
      fHistoTrTr->Fill(1.5);
    }
    else {
      fHistoTrTr->Fill(0.5);
    }

    fHistoLo->Fill( muonTrack->LoCircuit() );

    fHistoTheta->Fill( muonTrack->Theta() );  // [rad]
    fHistoPhi->Fill( muonTrack->Phi() );      // [rad]
    fHistoP->Fill( muonTrack->P() );          // [GeV/c]
    fHistoDca->Fill( muonTrack->GetDCA() );   // [cm]
    */

    if (fTrigChEff) {
      //Bool_t bp, nbp;
      //fTrigChEff->IsTriggered( 1100, muonTrack->LoCircuit(), bp, nbp );

      Float_t rb[4];
      Float_t rn[4];

      for (Int_t i=0; i<4; i++) {
        Int_t detElemId = 1000+100*(i+1);

        rb[i] = fTrigChEff->GetCellEfficiency(detElemId,
          muonTrack->LoCircuit(), AliMUONTriggerEfficiencyCells::kBendingEff);

        rn[i] = fTrigChEff->GetCellEfficiency(detElemId,
          muonTrack->LoCircuit(),
          AliMUONTriggerEfficiencyCells::kNonBendingEff);
      }

      Float_t effb =   rb[0]    *   rb[1]    *   rb[2]    *   rb[3]    +
                     (1.-rb[0]) *   rb[1]    *   rb[2]    *   rb[3]    +
                       rb[0]    * (1.-rb[1]) *   rb[2]    *   rb[3]    +
                       rb[0]    *   rb[1]    * (1.-rb[2]) *   rb[3]    +
                       rb[0]    *   rb[1]    *   rb[2]    * (1.-rb[3]);

      Float_t effn =   rn[0]    *   rn[1]    *   rn[2]    *   rn[3]    +
                     (1.-rn[0]) *   rn[1]    *   rn[2]    *   rn[3]    +
                       rn[0]    * (1.-rn[1]) *   rn[2]    *   rn[3]    +
                       rn[0]    *   rn[1]    * (1.-rn[2]) *   rn[3]    +
                       rn[0]    *   rn[1]    *   rn[2]    * (1.-rn[3]);

      Bool_t trb = (gRandom->Rndm() < effb);
      Bool_t trn = (gRandom->Rndm() < effn);
      Bool_t tr = (trb && trn);

      if ( AliAnalysisManager::GetAnalysisManager()->GetDebugLevel() >= 2 ) {

        AliInfo(Form("MTR: %s | MTK: %s", (tri ? "Yes" : "No"),
          (tra ? "Yes" : "No")));
        AliInfo(Form("Rb: %4.2f %4.2f %4.2f %4.2f => %6.4f", rb[0], rb[1], rb[2],
          rb[3], effb));
        AliInfo(Form("Rn: %4.2f %4.2f %4.2f %4.2f => %6.4f", rn[0], rn[1], rn[2],
          rn[3], effn));
      }

      if ( AliAnalysisManager::GetAnalysisManager()->GetDebugLevel() >= 1 ) {
      
        AliInfo(Form("Trb: %s | Trn: %s => %s", (trb ? "Yes" : "No"),
          (trn ? "Yes" : "No"), (tr ? "\033[32;1mACCEPTED\033[m" :
          "\033[31;1mREJECTED\033[m")));
      }

      // NON BENDING AND BENDING EFFICIENCIES ARE _ALWAYS_ EQUAL?!?!?!?!?!?

    }

  } // track loop

  fTreeOut->Fill();  // data is posted to the tree

  // Output data is posted
  PostData(1, fTreeOut);
  PostData(2, fHistoList);

}      

/** Called at the end of the analysis, to eventually plot the merged results:
 *  it makes sense only with the AliEn plugin, in local mode or in PROOF mode.
 */
void AliAnalysisTaskExtractMuonTracks::Terminate(Option_t *) {

  fHistoList = dynamic_cast<TList *>( GetOutputData(2) );
  if (!fHistoList) {
    AliError("Output list not available");
    return;
  }

  TH1F *histpt = dynamic_cast<TH1F *>( fHistoList->FindObject("histpt") );
  if (histpt) {
    gROOT->SetStyle("Plain");
    gStyle->SetPalette(1);
    TCanvas *c = new TCanvas("cpt", "Pt distribution");
    c->cd();
    histpt->DrawCopy();
  }
  else {
    AliError("Pt distribution histogram not available");
  }

}

/** The constructor of the Event class. It takes two arguments: the file name
 *  of the ESD and the "number of event", whatever it means to you (it will be
 *  usually set as the number of event inside the ESD file).
 */
Event::Event(const char *esdFileName, Int_t evNum) :
  TObject(),
  fTracks( new TClonesArray("AliESDMuonTrack", 10) ),
  fESDFileName(esdFileName),
  fEventInList(evNum)
{
}

/** Destructor for the Event class.
 */
Event::~Event() {
  delete fTracks;
}
