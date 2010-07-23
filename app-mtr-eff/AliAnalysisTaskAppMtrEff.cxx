#include "AliAnalysisTaskAppMtrEff.h"

ClassImp(AliAnalysisTaskAppMtrEff)

Int_t AliAnalysisTaskAppMtrEff::kNTrigLo =
  AliMUONConstants::NTriggerCircuit();  // 1 to 234

Int_t AliAnalysisTaskAppMtrEff::kNTrigCh =
  AliMUONConstants::NTriggerCh();  // 4

Int_t AliAnalysisTaskAppMtrEff::kNRpc = 18;  // 0 to 17

Int_t AliAnalysisTaskAppMtrEff::kLoRpc[234] = { 26, 27, 28, 29, 48, 49, 50, 51,
  68, 69, 84, 85, 100, 101, 113, 9, 10, 11, 30, 31, 32, 33, 52, 53, 54, 55, 70,
  71, 86, 87, 102, 103, 114, 12, 13, 34, 35, 56, 57, 72, 73, 88, 89, 104, 105,
  115, 14, 15, 36, 37, 58, 59, 74, 75, 90, 91, 106, 107, 116, 16, 38, 60, 76,
  92, 108, 117, 133, 155, 177, 193, 209, 225, 234, 131, 132, 153, 154, 175, 176,
  191, 192, 207, 208, 223, 224, 233, 129, 130, 151, 152, 173, 174, 189, 190,
  205, 206, 221, 222, 232, 126, 127, 128, 147, 148, 149, 150, 169, 170, 171,
  172, 187, 188, 203, 204, 219, 220, 231, 143, 144, 145, 146, 165, 166, 167,
  168, 185, 186, 201, 202, 217, 218, 230, 123, 124, 125, 139, 140, 141, 142,
  161, 162, 163, 164, 183, 184, 199, 200, 215, 216, 229, 121, 122, 137, 138,
  159, 160, 181, 182, 197, 198, 213, 214, 228, 119, 120, 135, 136, 157, 158,
  179, 180, 195, 196, 211, 212, 227, 118, 134, 156, 178, 194, 210, 226, 1, 17,
  39, 61, 77, 93, 109, 2, 3, 18, 19, 40, 41, 62, 63, 78, 79, 94, 95, 110, 4, 5,
  20, 21, 42, 43, 64, 65, 80, 81, 96, 97, 111, 6, 7, 8, 22, 23, 24, 25, 44, 45,
  46, 47, 66, 67, 82, 83, 98, 99, 112 };

Int_t AliAnalysisTaskAppMtrEff::kNLoPerRpc[18] = { 15, 18, 13, 13, 7, 7, 13, 13,
  18, 15, 18, 13, 13, 7, 7, 13, 13, 18 };

/** Constructor for the analysis task. It has some optional arguments that, if
 *  given, make the analysis also set a flag if the event was triggered or not
 *  by using a trigger decision added "a posteriori" from the R tables in OCDB.
 */
AliAnalysisTaskAppMtrEff::AliAnalysisTaskAppMtrEff(
  const char *name, Bool_t applyEfficiencies, Int_t runNum,
  const char *ocdbTrigChEff) :
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
    man->SetRun(runNum);

    AliCDBEntry *entry = man->Get("MUON/Calib/TriggerEfficiency");
    TObject *obj = entry->GetObject();

    fTrigChEff = new AliMUONTriggerChamberEfficiency(
      dynamic_cast<AliMUONTriggerEfficiencyCells*>(obj)
    );

    // Averages adjacent RPC efficiencies to be used when a track crosses
    // different RPCs
    fEffCh  = new Float_t[kNTrigCh*2];
    fEffRpc = new Float_t[kNRpc*kNTrigCh*2];

    /*
    // Check: RPC from Lo
    for (Int_t i=1; i<=kNTrigLo; i++) {
      Printf("lo=%d rpc=%d", i, GetRpcFromLo(i));
    }

    // Check: Lo from RPC
    Int_t *los;
    Int_t nLos;
    for (Int_t i=0; i<kNRpc; i++) {
      nLos = GetLosFromRpc(i, &los);
      printf("rpc=%d #lo=%d los={", i, nLos);
      for (Int_t j=0; j<nLos; j++) {
        printf("%d", los[j]);
        if (j<nLos-1) printf(",");
      }
      printf("}\n");
    }
    */

    // Average chamber efficiency
    for (Int_t ch=0; ch<kNTrigCh; ch++) {
      Int_t detElemId = 1000+100*(ch+1);
      Float_t effBend = 0.;
      Float_t effNonBend = 0.;
      for (Int_t lo=1; lo<=kNTrigLo; lo++) {
        effBend += fTrigChEff->GetCellEfficiency(detElemId, lo,
          AliMUONTriggerEfficiencyCells::kBendingEff);
        effNonBend += fTrigChEff->GetCellEfficiency(detElemId, lo,
          AliMUONTriggerEfficiencyCells::kNonBendingEff);
      }
      effBend /= (Float_t)kNTrigLo;
      effNonBend /= (Float_t)kNTrigLo;

      //Printf("ch=%d effb=%.4f effn=%.4f", detElemId, effBend, effNonBend);

      //Printf("fEffCh[%d] = %.4f  // bending",
      //  ch+AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh, effBend);
      //Printf("fEffCh[%d] = %.4f  // nonbending",
      //  ch+AliMUONTriggerEfficiencyCells::kNonBendingEff*kNTrigCh, effNonBend);

      fEffCh[ch+AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh] = effBend;
      fEffCh[ch+AliMUONTriggerEfficiencyCells::kNonBendingEff*kNTrigCh] =
        effNonBend;
    }

    /*
    const Float_t *ccb;
    const Float_t *ccn;
    ccb = GetChamberEff(AliMUONTriggerEfficiencyCells::kNonBendingEff);
    ccn = GetChamberEff(AliMUONTriggerEfficiencyCells::kBendingEff);
    for (Int_t k=0; k<kNTrigCh; k++) {
      Int_t detElemId = 1000+100*(k+1);
      Printf("ch=%d effb=%.4f effn=%.4f // cross-check", detElemId, ccb[k],
        ccn[k]);
    }
    */

    // Average RPC efficiency
    for (Int_t rpc=0; rpc<kNRpc; rpc++) {
      Int_t *los;
      Int_t nLos;
      nLos = GetLosFromRpc(rpc, &los);
      //printf("rpc=%02d #lo=%02d los={", rpc, nLos);

      for (Int_t ch=0; ch<kNTrigCh; ch++) {
        Int_t detElemId = 1000+100*(ch+1);
        Float_t effBend = 0.;
        Float_t effNonBend = 0.;

        /*b = fTrigChEff->GetCellEfficiency(detElemId, los[j],
          AliMUONTriggerEfficiencyCells::kBendingEff);
        n = fTrigChEff->GetCellEfficiency(detElemId, los[j],
          AliMUONTriggerEfficiencyCells::kNonBendingEff);*/

        //printf("(%.2f,%.2f)", b, n);

        for (Int_t j=0; j<nLos; j++) {
          effBend += fTrigChEff->GetCellEfficiency(detElemId, los[j],
            AliMUONTriggerEfficiencyCells::kBendingEff);
          effNonBend += fTrigChEff->GetCellEfficiency(detElemId, los[j],
            AliMUONTriggerEfficiencyCells::kNonBendingEff);
        }

        // These are (average) bending and nonbending efficiencies for the given
        // RPC and chamber
        effBend /= (Float_t)nLos;
        effNonBend /= (Float_t)nLos;
        //fEffRpc[rpc*(kNRpc*2)+AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh] =
        //  effBend;
        //fEffRpc[rpc*(kNRpc*2)+AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh] =
        //  effNonBend;

        //printf("%d(b=%.2f,n=%.2f)", ch, effBend, effNonBend);

        Int_t ib = rpc*(kNTrigCh*2) +
          AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh+ch;
        Int_t in = rpc*(kNTrigCh*2) +
          AliMUONTriggerEfficiencyCells::kNonBendingEff*kNTrigCh+ch;

        fEffRpc[ib] = effBend;
        fEffRpc[in] = effNonBend;

        //if (ch<kNTrigCh-1) printf(",");
      }

      //printf("}\n");      

      /*
      // Cross-check
      const Float_t *ccb;
      const Float_t *ccn;
      ccb = GetRpcEff(rpc, AliMUONTriggerEfficiencyCells::kNonBendingEff);
      ccn = GetRpcEff(rpc, AliMUONTriggerEfficiencyCells::kBendingEff);
      printf("rpc=%02d        los={", rpc);
      for (Int_t j=0; j<kNTrigCh; j++) {
        printf("%d(b=%.2f,n=%.2f)", j, ccb[j], ccn[j]);
        if (j<kNTrigCh-1) printf(",");
      }
      printf("} // cross-check\n\n");
      */

    }

    //gSystem->Exit(66);

  }

}

/** Destructor.
 */
AliAnalysisTaskAppMtrEff::~AliAnalysisTaskAppMtrEff() {
  if (fApplyEff) {
    delete[] fEffCh;
    delete[] fEffRpc;
  }
}

/** This function is called to create objects that store the output data. It is
 *  thus called only once when running the analysis.
 */
void AliAnalysisTaskAppMtrEff::UserCreateOutputObjects() {

  // Create output TTree
  fTreeOut = new TTree("muonTracks", "Muon tracks");
  fEvent = NULL;
  fTreeOut->Branch("Events", &fEvent);  // the branch "Events" holds objects of
                                        // class event
  // Output list of TH1Fs
  fHistoList = new TList();

  // Pt distribution
  fHistoPt = new TH1F("hPt", "Pt distribution", 100, 0., 4.);
  fHistoPt->GetXaxis()->SetTitle("Pt [GeV/c]");
  fHistoList->Add(fHistoPt);

  // Number of tracks: total, good for eff, 
  fHistoTrCnt = new TH1F("hTrCnt", "Tracks count", 3, 0.5, 3.5);
  fHistoTrCnt->GetXaxis()->SetBinLabel(kCntAll,  "all tracks");
  fHistoTrCnt->GetXaxis()->SetBinLabel(kCntEff,  "good for eff");
  fHistoTrCnt->GetXaxis()->SetBinLabel(kCntKept, "kept");
  fHistoList->Add(fHistoTrCnt);

  // Histogram with counts of some track types
  fHistoTrLoc = new TH1F("hTrLoc", "Tracks locations", 3, 0.5, 3.5);
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocTrig, "only trig");
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocTrack, "only track");
  fHistoTrLoc->GetXaxis()->SetBinLabel(kLocBoth, "trig+track");
  //fHistoList->Add(fHistoTrLoc);

  // Efficiency flags distribution
  fHistoEffFlag = new TH1F("hEffFlag", "Efficiency flags", 4, -0.5, 3.5);
  // kNoEff = 0, kChEff = 1, kSlatEff = 2, kBoardEff = 3
  fHistoEffFlag->GetXaxis()->SetBinLabel(1, "not good");
  fHistoEffFlag->GetXaxis()->SetBinLabel(2, "diff RPCs");
  fHistoEffFlag->GetXaxis()->SetBinLabel(3, "same RPC");
  fHistoEffFlag->GetXaxis()->SetBinLabel(4, "same board");
  //fHistoList->Add(fHistoEffFlag);

  // Kinematics: theta
  fHistoTheta = new TH1F("hTheta", "#theta distribution", 1000, 0.,
    TMath::Pi());
  fHistoTheta->GetXaxis()->SetTitle("#theta [rad]");
  //fHistoList->Add(fHistoTheta);

  // Kinematics: total momemtum
  fHistoP = new TH1F("hP", "Total momentum distribution", 1000, 0., 100.);
  fHistoP->GetXaxis()->SetTitle("P [GeV/c]");
  //fHistoList->Add(fHistoP);

  // Kinematics: phi
  fHistoPhi = new TH1F("hPhi", "#varphi distribution", 1000, 0.,
    2.*TMath::Pi());
  fHistoPhi->GetXaxis()->SetTitle("#varphi [rad]");
  //fHistoList->Add(fHistoPhi);

  // Kinematics: DCA
  fHistoDca = new TH1F("hDca", "DCA distribution", 1000, 0., 100.);
  fHistoDca->GetXaxis()->SetTitle("DCA [cm]");
  //fHistoList->Add(fHistoDca);

  // Hardware: chambers hit
  fHistoChHit = new TH1F("hChHit", "Chambers hit (per plane)", 8, -0.5, 7.5);
  //fHistoList->Add(fHistoChHit);

  // Hardware: number of chambers hit (bending plane)
  fHistoBendHit = new TH1F("hBendHit", "Signals (bending)", 5, -0.5, 4.5);
  //fHistoList->Add(fHistoBendHit);

  // Hardware: number of chambers hit (nonbending plane)
  fHistoNBendHit = new TH1F("hNBendHit", "Signals (nonbending)", 5, -0.5, 4.5);
  //fHistoList->Add(fHistoNBendHit);

}

/** This code is the core of the analysis: it is executed once per event. At
 *  each loop, fInputEvent of type AliESDEvent points to the current event.
 */
void AliAnalysisTaskAppMtrEff::UserExec(Option_t *) {

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

    AliESDMuonTrack *esdMt = esdEv->GetMuonTrack(iTrack);

    if (!esdMt) {
      AliError(Form("Could not receive track %d", iTrack));
      continue;
    }

    AliESDMuonTrack* muonTrack = new AliESDMuonTrack( *esdMt );

    fHistoTrCnt->Fill(kCntAll);  ///< Count all tracks

    Bool_t tri = muonTrack->ContainTriggerData();
    Bool_t tra = muonTrack->ContainTrackerData();
    UShort_t effFlag = AliESDMuonTrack::GetEffFlag(
      muonTrack->GetHitsPatternInTrigCh() );

    if ((!tri) || (!tra) || (effFlag == AliESDMuonTrack::kNoEff)) {
      AliDebug(1, "Track does not match both trigger and tracker, or it is not "
        "good for efficiency calculation");
      delete muonTrack;
      continue;
    }

    fHistoTrCnt->Fill(kCntEff);  ///< Count tracks good for efficiency

    // Apply the efficiency "a posteriori" (if told to do so)
    if (fApplyEff) {
      if (!KeepTrackByEff(muonTrack)) {
        AliDebug(1, "Track discarded");
        delete muonTrack;
        continue;
      }
      AliDebug(1, "Track kept");
    }

    /////////////////////////////////////////////////////////
    // From this point on, muonTrack is the KEPT muonTrack //
    /////////////////////////////////////////////////////////

    new (ta[n++]) AliESDMuonTrack(*muonTrack);

    fHistoTrCnt->Fill(kCntKept);  ///< Count tracks kept

    fHistoPt->Fill(muonTrack->Pt());          // [GeV/c]
    fHistoTheta->Fill( muonTrack->Theta() );  // [rad]
    fHistoPhi->Fill( muonTrack->Phi() );      // [rad]
    fHistoP->Fill( muonTrack->P() );          // [GeV/c]
    fHistoDca->Fill( muonTrack->GetDCA() );   // [cm]

    fHistoEffFlag->Fill(effFlag);

    Int_t hitsNBend = 0;
    Int_t hitsBend = 0;

    for (Int_t i=0; i<4; i++) { // chamber (0 to 3)
      for (Int_t j=0; j<2; j++) { // cathode (0, 1)
        Bool_t hit = AliESDMuonTrack::IsChamberHit(
          muonTrack->GetHitsPatternInTrigCh(), j, i); ///< ptn, cath, chamb
        if (hit) {
          fHistoChHit->Fill( 2.*i + j );
          (j == AliMUONTriggerEfficiencyCells::kNonBendingEff) ?
            hitsNBend++ : hitsBend++;
        }
      }
    }

    fHistoBendHit->Fill(hitsBend);
    fHistoNBendHit->Fill(hitsNBend);

    // Fill histogram with track locations
    if ((tri) && (tra)) { fHistoTrLoc->Fill( kLocBoth ); }
    else if (tri)       { fHistoTrLoc->Fill( kLocTrig ); }
    else if (tra)       { fHistoTrLoc->Fill( kLocTrack ); }

  } // track loop

  fTreeOut->Fill();  // data is posted to the tree

  // Output data is posted
  PostData(1, fTreeOut);
  PostData(2, fHistoList);

}      

/** Called at the end of the analysis, to eventually plot the merged results:
 *  it makes sense only with the AliEn plugin, in local mode or in PROOF mode.
 */
void AliAnalysisTaskAppMtrEff::Terminate(Option_t *) {

  fHistoList = dynamic_cast<TList *>( GetOutputData(2) );
  if (!fHistoList) {
    AliError("Output list not available");
    return;
  }

  gROOT->SetStyle("Plain");
  gStyle->SetPalette(1);

  Printf("\n");  ///< Clean-up output

  TH1F *h;
  TIter i(fHistoList);

  while (( h = dynamic_cast<TH1F *>(i.Next()) )) {
    new TCanvas(Form("canvas_%s", h->GetName()), h->GetTitle());
    h->DrawCopy();

    if (strcmp(h->GetName(), "hTrCnt") == 0) {
      Float_t eff = h->GetBinContent(kCntKept) / h->GetBinContent(kCntEff);
      AliInfo(Form("Efficiency: %.5f", eff));
    }

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

/** Decides whether to keep the specified muon track or not by using efficiency
 *  values from the OCDB. It returns kTRUE if track has to be kept, kFALSE if it
 *  has to be rejected.
 */
Bool_t AliAnalysisTaskAppMtrEff::KeepTrackByEff(
  AliESDMuonTrack *muTrack) const {

  UShort_t effFlag = AliESDMuonTrack::GetEffFlag(
    muTrack->GetHitsPatternInTrigCh());

  // In this case, track is not good for efficiency calculation; we should not
  // count it even in total tracks, take care!
  if (effFlag == AliESDMuonTrack::kNoEff) {
    return kFALSE;
  }

  Float_t rb[kNTrigCh]; ///< Efficiencies for the bending plane
  Float_t rn[kNTrigCh]; ///< Efficiencies for the nonbending plane

  GetTrackEffPerCrossedElements(muTrack, rb, rn);

  //AliInfo(Form("RPC number for this lo (%d) is: %d", muTrack->LoCircuit(),
  //  AliESDMuonTrack::GetSlatOrInfo(muTrack->GetHitsPatternInTrigCh()) ));

  Float_t mtrEffBend  =   rb[0]    *   rb[1]    *   rb[2]    *   rb[3]    +
                        (1.-rb[0]) *   rb[1]    *   rb[2]    *   rb[3]    +
                          rb[0]    * (1.-rb[1]) *   rb[2]    *   rb[3]    +
                          rb[0]    *   rb[1]    * (1.-rb[2]) *   rb[3]    +
                          rb[0]    *   rb[1]    *   rb[2]    * (1.-rb[3]);

  Float_t mtrEffNBend =   rn[0]    *   rn[1]    *   rn[2]    *   rn[3]    +
                        (1.-rn[0]) *   rn[1]    *   rn[2]    *   rn[3]    +
                          rn[0]    * (1.-rn[1]) *   rn[2]    *   rn[3]    +
                          rn[0]    *   rn[1]    * (1.-rn[2]) *   rn[3]    +
                          rn[0]    *   rn[1]    *   rn[2]    * (1.-rn[3]);

  Bool_t hitBend  = (gRandom->Rndm() < mtrEffBend);
  Bool_t hitNBend = (gRandom->Rndm() < mtrEffNBend);

  AliDebug(1, Form("Effs (bend): %4.2f %4.2f %4.2f %4.2f => %6.4f", rb[0],
    rb[1], rb[2], rb[3], mtrEffBend));
  AliDebug(1, Form("Effs (nbnd): %4.2f %4.2f %4.2f %4.2f => %6.4f", rn[0],
    rn[1], rn[2], rn[3], mtrEffNBend));

  return ((hitBend) && (hitNBend));
}

/**
 */
void AliAnalysisTaskAppMtrEff::GetTrackEffPerCrossedElements(
  AliESDMuonTrack *muTrack, Float_t *effBend, Float_t *effNonBend) const {

  UShort_t effFlag = AliESDMuonTrack::GetEffFlag(
    muTrack->GetHitsPatternInTrigCh() );

  if (effFlag == AliESDMuonTrack::kNoEff) {
    for (Int_t i=0; i<kNTrigCh; i++) {
      effBend[i]    = 0.;
      effNonBend[i] = 0.;
    }
  }
  else if (effFlag == AliESDMuonTrack::kChEff) {

    // Track crosses different RPCs
    AliDebug(2, "Track crosses different RPCs");

    const Float_t *chBend;
    const Float_t *chNonBend;
    chBend = GetChamberEff(AliMUONTriggerEfficiencyCells::kNonBendingEff);
    chNonBend = GetChamberEff(AliMUONTriggerEfficiencyCells::kBendingEff);

    memcpy(effBend, chBend, sizeof(Float_t)*kNTrigCh);
    memcpy(effNonBend, chNonBend, sizeof(Float_t)*kNTrigCh);

  }
  else if (effFlag == AliESDMuonTrack::kSlatEff) {

    // Track hits the same RPC on all chambers
    Int_t rpc = AliESDMuonTrack::GetSlatOrInfo(
      muTrack->GetHitsPatternInTrigCh() );

    AliDebug(2, Form("Track stays on the same RPC: %d", rpc));

    const Float_t *chBend;
    const Float_t *chNonBend;
    chBend = GetRpcEff(rpc, AliMUONTriggerEfficiencyCells::kNonBendingEff);
    chNonBend = GetRpcEff(rpc, AliMUONTriggerEfficiencyCells::kBendingEff);

    memcpy(effBend, chBend, sizeof(Float_t)*kNTrigCh);
    memcpy(effNonBend, chNonBend, sizeof(Float_t)*kNTrigCh);

  }
  else if (effFlag == AliESDMuonTrack::kBoardEff) {

    AliDebug(2, "Track stays on the same Local Board");

    // Track hits the same local board on all chambers
    Int_t localBoard = muTrack->LoCircuit();

    for (Int_t i=0; i<kNTrigCh; i++) {
      Int_t detElemId = 1000+100*(i+1);
      effBend[i] = fTrigChEff->GetCellEfficiency(detElemId, localBoard,
        AliMUONTriggerEfficiencyCells::kBendingEff);
      effNonBend[i] = fTrigChEff->GetCellEfficiency(detElemId, localBoard,
        AliMUONTriggerEfficiencyCells::kNonBendingEff);
    }

  }

}

/**
 */
const Float_t *AliAnalysisTaskAppMtrEff::GetRpcEff(Int_t nRpc,
  Int_t bendNonBend) const {

  //AliMUONTriggerEfficiencyCells::kBendingEff = 0;
  //AliMUONTriggerEfficiencyCells::kBendingEff = 1;

  // nRpc = [0,17]

  if (((bendNonBend != 0) && (bendNonBend != 1)) ||
    (nRpc < 0) || (nRpc >= kNRpc))
    return NULL;

  // Take care of considering the first 4 values, which is: one for each plane
  return &fEffRpc[ (nRpc * 8) + (bendNonBend * 4) ];
}

const Float_t *AliAnalysisTaskAppMtrEff::GetChamberEff(
  Int_t bendNonBend) const {

  //AliMUONTriggerEfficiencyCells::kBendingEff = 0;
  //AliMUONTriggerEfficiencyCells::kBendingEff = 1;

  // nRpc = [0,3]

  if ((bendNonBend != 0) && (bendNonBend != 1))
    return NULL;

  // Take care of considering the first 4 values, which is: one for each plane
  return &fEffCh[ bendNonBend * 4 ];
}

/**
 */
Int_t AliAnalysisTaskAppMtrEff::GetRpcFromLo(Int_t lo) const {

  // Local board index goes to 1 to 234;
  // RPC index goes to 0 to 17;

  if ((lo <= 0) || (lo > kNTrigLo)) return -1;

  // kLoRpc (234)
  // kNRpc (18)

  // Find index
  Int_t idx;
  Int_t nRpc = 0;
  Int_t nInRpc = 0;
  //printf("{{{ ");
  for (idx=0; idx<kNTrigLo; idx++) {
    if (nInRpc == kNLoPerRpc[nRpc]) {
      nRpc++;
      nInRpc = 0;
    }
    nInRpc++;
    //printf("%d ", nInRpc);
    if (lo == kLoRpc[idx]) break;
  }
  //printf("}}}\n");

  return nRpc;
}

/**
 */
Int_t AliAnalysisTaskAppMtrEff::GetLosFromRpc(Int_t rpc, Int_t **los) const {

  if (los == NULL) return -1;
  if ((rpc < 0) || (rpc >= kNRpc)) return -1;

  Int_t startIdx = 0;

  for (Int_t i=0; i<rpc; i++) {
    startIdx += kNLoPerRpc[i];
  }

  *los = &kLoRpc[startIdx];
  return kNLoPerRpc[rpc];
}
