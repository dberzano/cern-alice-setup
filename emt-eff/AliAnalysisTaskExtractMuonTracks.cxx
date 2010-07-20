#include "AliAnalysisTaskExtractMuonTracks.h"

ClassImp(AliAnalysisTaskExtractMuonTracks)

/** Constructor for the analysis task. It has some optional arguments that, if
 *  given, make the analysis also set a flag if the event was triggered or not
 *  by using a trigger decision added "a posteriori" from the R tables in OCDB.
 */
AliAnalysisTaskExtractMuonTracks::AliAnalysisTaskExtractMuonTracks(
  const char *name, Bool_t applyEfficiencies, Int_t runNum,
  const char *ocdbTrigChEff, const char *ocdbMagField) :
    AliAnalysisTaskSE(name),
    fTreeOut(0),
    fEvent(0),
    fApplyEff(applyEfficiencies)
{
  // Input slot #0 works with a TChain
  DefineInput(0, TChain::Class());

  // Output slot #0 is already defined in base class

  // Output slot #1 writes into a TNtuple container
  DefineOutput(1, TTree::Class());

  // Output slot #2 writes into a TList of histograms
  DefineOutput(2, TList::Class());

  // Decides if to apply or not the trigger decision
  if (fApplyEff) {

    AliCDBManager *man = AliCDBManager::Instance();
    man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");
    if (ocdbTrigChEff) {
      man->SetSpecificStorage("MUON/Calib/TriggerEfficiency", ocdbTrigChEff);
    }
    if (ocdbMagField) {
      man->SetSpecificStorage("GRP/GRP/Data", ocdbMagField);
    }
    man->SetRun(runNum);

    AliCDBEntry *entry = man->Get("MUON/Calib/TriggerEfficiency");
    TObject *obj = entry->GetObject();

    fTrigChEff = new AliMUONTriggerChamberEfficiency(
      dynamic_cast<AliMUONTriggerEfficiencyCells*>(obj)
    );

    AliMUONCDB::LoadField();

  }

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
  fHistoPt = new TH1F("hPt", "Pt distribution", 100, 0., 4.);
  fHistoPt->GetXaxis()->SetTitle("Pt [GeV/c]");
  fHistoList->Add(fHistoPt);

  // Histogram with counts of some track types
  fHistoTrLoc = new TH1F("hTrLoc", "Tracks locations", 3, 0.5, 3.5);
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocTrig, "only trig");
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocTrack, "only track");
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocBoth, "trig+track");
  fHistoList->Add(fHistoTrLoc);

  // Efficiency flags distribution
  fHistoEffFlag = new TH1F("hEffFlag", "Efficiency flags", 4, -0.5, 3.5);
  // kNoEff = 0, kChEff = 1, kSlatEff = 2, kBoardEff = 3
  fHistoEffFlag->GetXaxis()->SetBinLabel(1, "not good");
  fHistoEffFlag->GetXaxis()->SetBinLabel(2, "diff RPCs");
  fHistoEffFlag->GetXaxis()->SetBinLabel(3, "same RPC");
  fHistoEffFlag->GetXaxis()->SetBinLabel(4, "same board");
  fHistoList->Add(fHistoEffFlag);

  // Kinematics: theta
  fHistoTheta = new TH1F("hTheta", "#theta distribution", 1000, 0.,
    TMath::Pi());
  fHistoTheta->GetXaxis()->SetTitle("#theta [rad]");
  fHistoList->Add(fHistoTheta);

  // Kinematics: total momemtum
  fHistoP = new TH1F("hP", "Total momentum distribution", 1000, 0., 100.);
  fHistoP->GetXaxis()->SetTitle("P [GeV/c]");
  fHistoList->Add(fHistoP);

  // Kinematics: phi
  fHistoPhi = new TH1F("hPhi", "#varphi distribution", 1000, 0.,
    2.*TMath::Pi());
  fHistoPhi->GetXaxis()->SetTitle("#varphi [rad]");
  fHistoList->Add(fHistoPhi);

  // Kinematics: DCA
  fHistoDca = new TH1F("hDca", "DCA distribution", 1000, 0., 100.);
  fHistoDca->GetXaxis()->SetTitle("DCA [cm]");
  fHistoList->Add(fHistoDca);

  // Hardware: chambers hit
  fHistoChHit = new TH1F("hChHit", "Chambers hit (per plane)", 8, -0.5, 7.5);
  fHistoList->Add(fHistoChHit);

  // Hardware: number of chambers hit (bending plane)
  fHistoBendHit = new TH1F("hBendHit", "Signals (bending)", 5, -0.5, 4.5);
  fHistoList->Add(fHistoBendHit);

  // Hardware: number of chambers hit (nonbending plane)
  fHistoNBendHit = new TH1F("hNBendHit", "Signals (nonbending)", 5, -0.5, 4.5);
  fHistoList->Add(fHistoNBendHit);

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

    Bool_t tri = muonTrack->ContainTriggerData();
    Bool_t tra = muonTrack->ContainTrackerData();

    fHistoPt->Fill(muonTrack->Pt());          // [GeV/c]
    fHistoTheta->Fill( muonTrack->Theta() );  // [rad]
    fHistoPhi->Fill( muonTrack->Phi() );      // [rad]
    fHistoP->Fill( muonTrack->P() );          // [GeV/c]
    fHistoDca->Fill( muonTrack->GetDCA() );   // [cm]

    fHistoEffFlag->Fill(
      AliESDMuonTrack::GetEffFlag( muonTrack->GetHitsPatternInTrigCh() )
    );

    Int_t hitsNBend = 0;
    Int_t hitsBend = 0;

    for (Int_t i=0; i<4; i++) { // chamber (0 to 3)
      for (Int_t j=0; j<2; j++) { // cathode (0, 1)
        Bool_t hit = AliESDMuonTrack::IsChamberHit(
          muonTrack->GetHitsPatternInTrigCh(), j, i); ///< ptn, cath, chamb
        if (hit) {
          fHistoChHit->Fill( 2.*i + j );
          (j == 0) ? hitsBend++ : hitsNBend++;  ///< 0 is bending?
        }
      }
    }

    fHistoBendHit->Fill(hitsBend);
    fHistoNBendHit->Fill(hitsNBend);

    // Fill histogram with track locations
    if ((tri) && (tra)) { fHistoTrLoc->Fill( kLocBoth ); }
    else if (tri)       { fHistoTrLoc->Fill( kLocTrig ); }
    else if (tra)       { fHistoTrLoc->Fill( kLocTrack ); }

    if (fApplyEff) {
      KeepTrackByEff(muonTrack); 
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

  gROOT->SetStyle("Plain");
  gStyle->SetPalette(1);

  TH1F *h;
  TIter i(fHistoList);

  while (( h = dynamic_cast<TH1F *>(i.Next()) )) {
    new TCanvas(Form("canvas_%s", h->GetName()), h->GetTitle());
    h->DrawCopy();
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

// Fa, in effetti, differenza: questo per l'ultima traccia:
//I-AliAnalysisTaskExtractMuonTracks::UserExec: Extrapolated to MT11 [cm]: z=-1603.500000, bend=52.772428, nonbend=-150.282259
//I-AliAnalysisTaskExtractMuonTracks::UserExec: Extrapolated to MT11 [cm]: z=-1603.500000, bend=12.627187, nonbend=-149.924941
//I-AliAnalysisTaskExtractMuonTracks::UserExec: Extrapolated to MT11 [cm]: z=-1603.500000, bend=52.626195, nonbend=-150.185043


/** Decides whether to keep the specified muon track or not by using efficiency
 *  values from the OCDB.
 */
Bool_t AliAnalysisTaskExtractMuonTracks::KeepTrackByEff(AliESDMuonTrack *muTrack) {

  /*Float_t rb[4]; ///< Efficiencies for the bending plane
  Float_t rn[4]; ///< Efficiencies for the nonbending plane

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
    AliInfo(Form("Rb: %4.2f %4.2f %4.2f %4.2f => %6.4f", rb[0], rb[1],
      rb[2], rb[3], effb));
    AliInfo(Form("Rn: %4.2f %4.2f %4.2f %4.2f => %6.4f", rn[0], rn[1],
      rn[2], rn[3], effn));
  }

  if ( AliAnalysisManager::GetAnalysisManager()->GetDebugLevel() >= 1 ) {
    AliInfo(Form("Trb: %s | Trn: %s => %s", (trb ? "Yes" : "No"),
      (trn ? "Yes" : "No"), (tr ? "\033[32;1mACCEPTED\033[m" :
      "\033[31;1mREJECTED\033[m")));
  }
  */

  AliInfo(Form("Called: %x", muTrack));

  return kTRUE;
}
