#if !defined(__CINT__) || defined(__MAKECINT__)

// ROOT includes
#include <Riostream.h>
#include <TString.h>
#include <TFile.h>
#include <TMath.h>
#include <TPRegexp.h>
#include <TH1F.h>

// AliRoot includes
#include <AliMUONTriggerEfficiencyCells.h>

#endif

////////////////////////////////////////////////////////////////////////////////
// Gets efficiency type as a string by cathode number
////////////////////////////////////////////////////////////////////////////////
TString GetTypeStrByCath(Int_t nCath) {

  TString cathStr;

  switch (nCath) {

    case AliMUONTriggerEfficiencyCells::kBendingEff: // usually: 0
      cathStr = "bendPlane";
    break;

    case AliMUONTriggerEfficiencyCells::kNonBendingEff: // usually: 1
      cathStr = "nonBendPlane";
    break;

    case AliMUONTriggerEfficiencyCells::kBothPlanesEff: // usually: 2
      cathStr = "bothPlanes";
    break;

  }

  return cathStr;
}

////////////////////////////////////////////////////////////////////////////////
// Creates a histogram that holds either numerators or denominators of per-board
// efficiencies
////////////////////////////////////////////////////////////////////////////////
TH1F *CreateBoardHisto(TString prefix, Int_t ch, TList *list) {
  TString name = Form("%sCountBoardCh%d", prefix.Data(), ch);
  TH1F *h = new TH1F(name, name, 234, 0.5, 234.5);
  h->GetXaxis()->SetTitle("board");
  h->GetYaxis()->SetTitle("counts");
  //Printf("Created: %s", h->GetName());
  if (list) list->Add(h);
  return h;
}

////////////////////////////////////////////////////////////////////////////////
// Converts a ROOT file with per-board efficiencies into a text file (old
// format)
////////////////////////////////////////////////////////////////////////////////
void RootToTxt(TString& in, TString& out, UInt_t effDecimals = 4) {

  // The ROOT file containing the TList
  TFile *f = TFile::Open(in);

  if (!f) {
    Printf("Can't open ROOT file %s", in.Data());
    return;
  }

  // List of histograms
  TList *list = (TList *)f->Get("triggerChamberEff");
  if (!list) {
    Printf("ROOT file does not contain the list of efficiencies");
    return;
  }

  // Output text file
  ofstream os(out);
  if (!out) {
    Printf("Can't write on %s", out.Data());
    f->Close();
    delete f;
    return;
  }

  // Cathode types
  const Int_t types[] = {
    AliMUONTriggerEfficiencyCells::kBendingEff,
    AliMUONTriggerEfficiencyCells::kNonBendingEff,
    AliMUONTriggerEfficiencyCells::kBothPlanesEff
  };
  const UInt_t nTypes = sizeof(types)/sizeof(Int_t);

  // Number of decimals
  const UInt_t effsPerLine = 80 / (effDecimals+3);
  TString effFmt = Form(" %%.%uf", effDecimals);

  // Header of text file
  os << "localBoards" << endl;

  // Search for histograms per plane
  for (UInt_t i=11; i<=14; i++) {

    // Search for denominators first
    TString denName = Form("allTracksCountBoardCh%u", i);
    TH1 *hDen = (TH1 *)list->FindObject(denName.Data());

    if (!hDen) {
      Printf("Denominators not found for chamber %u, skipping chamber", i);
      continue;
    }

    os << endl << Form("detElemId:\t%u00", i) << endl;

    // Search for numerators
    for (UInt_t j=0; j<nTypes; j++) {
      TString typeStr = GetTypeStrByCath(types[j]);
      TString name = Form("%sCountBoardCh%u", typeStr.Data(), i);

      TH1 *hNum = (TH1 *)list->FindObject(name.Data());
      if (!hNum) {
        Printf("Can't find %s, skipping", name.Data());
        continue;
      }

      os << Form(" cathode:\t%d", types[j]) << endl;

      // Output formatted efficiencies
      UInt_t nOnLine = 0;
      for (Int_t k=1; k<=234; k++) {
        Int_t bin = hNum->GetBin(k);
        Float_t den = hDen->GetBinContent(bin);
        Float_t num = hNum->GetBinContent(bin);
        Float_t eff = num/den;
        os << Form(effFmt.Data(), eff);
        if ((++nOnLine == effsPerLine) && (k < 234)) {
          nOnLine = 0;
          os << endl;
        }
      }

      os << endl << endl;

    }

  }

  os.close();
  f->Close();
  delete f;

}

////////////////////////////////////////////////////////////////////////////////
// Converts a text file (old format) with per-board efficiencies into a ROOT
// file
////////////////////////////////////////////////////////////////////////////////
void TxtToRoot(TString& in, TString& out) {

  ifstream is(in);
  if (!is) {
    Printf("Can't open %s", in.Data());
    return;
  }

  Char_t buf[1000];
  TPMERegexp reCham("^[ \t]*detElemId:[ \t]*([0-9]+)[ \t]*$");
  TPMERegexp reCath("^[ \t]*cathode:[ \t]*([0-9]+)[ \t]*$");
  Int_t nCham = -1;
  Int_t nCath;
  Int_t nChamShort = -1;

  // Multiply everything by factor, to deal with TGraphAsymmErrors which is used
  // to do the ratio between the histograms
  const Float_t factor = 1e3;

  // The containing list
  TList *list = new TList();

  // Dummy histograms for denominators
  for (UInt_t i=11; i<=14; i++) {
    TH1F *dummy = CreateBoardHisto("allTracks", i, list);
    UInt_t bins = dummy->GetNbinsX();
    for (UInt_t j=1; j<=bins; j++) {
      dummy->SetBinContent(j, factor); // so the ratio will be the efficiency
    }
  }

  // Main loop on all the lines
  while (is.getline(buf, 1000)) {

    if (reCham.Match(buf) == 2) {
      nCham = reCham[1].Atoi();
      if ((nCham == 0) || ((nCham % 100) != 0)) {
        Printf("Error: invalid chamber number: %s, skipping", reCham[1].Data());
        nCham = nChamShort = -1;
      }
      else {
        nChamShort = nCham / 100;
      }

    }
    else if ((nCham > -1) && (reCath.Match(buf) == 2)) {

      nCath = reCath[1].Atoi();
      TString cathStr = GetTypeStrByCath(nCath);

      if (cathStr.IsNull()) {
        Printf("Error: invalid cathode number: %s, skipping", reCath[1].Data());
        continue;
      }

      TH1F *hEffs = CreateBoardHisto(cathStr, nChamShort, list);

      // Read 234 values, one for each local board
      for (UInt_t i=1; i<=234; i++) {
        Float_t eff;
        is >> eff;
        Int_t bin = hEffs->GetBin(i);  // in principle, bin == i
        hEffs->SetBinContent(bin, TMath::Nint(factor*eff));
        //Printf("%s[%d] = %.2f // board %u", hEffs->GetName(), bin, eff, i);
      }

    }

  }

  is.close();

  // The ROOT file is filled with the TList
  TFile *f = TFile::Open(out, "recreate");
  list->Write("triggerChamberEff", TObject::kSingleKey);
  f->Close();
  delete f;
}

////////////////////////////////////////////////////////////////////////////////
// Automatically selects the way of conversion (txt <-> root)
////////////////////////////////////////////////////////////////////////////////
void MUONConvertTrigBoardEff(TString in, TString out) {

  if (in.EndsWith(".root")) {
    RootToTxt(in, out);
  }
  else if (out.EndsWith(".root")) {
    TxtToRoot(in, out);
  }
  else {
    Printf("At least one out of the two parameters must be a ROOT file name.");
  }

}
