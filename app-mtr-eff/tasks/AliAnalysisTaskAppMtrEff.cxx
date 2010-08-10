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
    AliAnalysisTask(name, name),
    fTreeMc(0x0),
    fTreeRec(0x0),
    fEventEsd(0x0),
    fEventMc(0x0),
    fApplyEff(applyEfficiencies),
    fNevt(0)
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

      fEffCh[ch+AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh] = effBend;
      fEffCh[ch+AliMUONTriggerEfficiencyCells::kNonBendingEff*kNTrigCh] =
        effNonBend;
    }

    // Average RPC efficiency
    for (Int_t rpc=0; rpc<kNRpc; rpc++) {
      Int_t *los;
      Int_t nLos;
      nLos = GetLosFromRpc(rpc, &los);

      for (Int_t ch=0; ch<kNTrigCh; ch++) {
        Int_t detElemId = 1000+100*(ch+1);
        Float_t effBend = 0.;
        Float_t effNonBend = 0.;

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

        Int_t ib = rpc*(kNTrigCh*2) +
          AliMUONTriggerEfficiencyCells::kBendingEff*kNTrigCh+ch;
        Int_t in = rpc*(kNTrigCh*2) +
          AliMUONTriggerEfficiencyCells::kNonBendingEff*kNTrigCh+ch;

        fEffRpc[ib] = effBend;
        fEffRpc[in] = effNonBend;
      }
    }

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
void AliAnalysisTaskAppMtrEff::CreateOutputObjects() {

  // TList of histograms (empty for the moment)
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

/**
 */
/** Used to connect input data from ESD or AOD to the analysis task. It is
 *  called only once.
 */
void AliAnalysisTaskAppMtrEff::ConnectInputData(Option_t *) {

  TTree* tree = dynamic_cast<TTree*>( GetInputData(0) );

  if (!tree) {
    AliError("Could not read chain from input slot 0");
    return;
  }

  // Disable all branches and enable only the needed ones
  // The next two lines are different when data produced as AliESDEvent is read
  tree->SetBranchStatus("*", kFALSE);
  tree->SetBranchStatus("MuonTracks.*", kTRUE);

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

  // Monte Carlo events
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

/** This code is the core of the analysis: it is executed once per event.
 */
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

  // Increment event counter
  fNevt++;

}      

/** Called at the end of the analysis.
 */
void AliAnalysisTaskAppMtrEff::Terminate(Option_t *) {}

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

  Float_t rb[kNTrigCh]; // Efficiencies for the bending plane
  Float_t rn[kNTrigCh]; // Efficiencies for the nonbending plane

  GetTrackEffPerCrossedElements(muTrack, rb, rn);

  //AliInfo(Form("RPC number for this lo (%d) is: %d", muTrack->LoCircuit(),
  //  AliESDMuonTrack::GetSlatOrInfo(muTrack->GetHitsPatternInTrigCh()) ));

  // CAN BE HEAVILY OPTIMIZED, IT IS JUST TO SEE THE FORMULA CLEARLY
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

/** Rapidity.
 */
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
