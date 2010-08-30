////////////////////////////////////////////////////////////////////////////////
//
// CompareResults.C -- by Dario Berzano <dario.berzano@gmail.com>
//
///////////////////////////////////////////////////////////////////////////////

// AnalysisTask output directory prefix
TString anaDir = "/dalice05/berzano/outana/app-mtr-eff";

// Base name of the output files
TString baseOut;

////////////////////////////////////////////////////////////////////////////////
// Main function
////////////////////////////////////////////////////////////////////////////////
void CompareResults() {

  // Ask for the simTag (automatically search in the outana dir)
  TString simsList = gSystem->GetFromPipe(
    Form("cd \"%s\" ; find . -type d -name 'sim-*' | sort | cut -b3-", anaDir.Data())
  );

  TString simTag;

  while (kTRUE) {

    Printf("\nChoose the type of simulation to analyze:\n");

    TObjArray *oa = simsList.Tokenize("\n\r");
    TObjString *os;
    TString s;
    for (UInt_t i=0; i<oa->GetEntries(); i++) {
      os = (TObjString *)oa->At(i);
      s = os->GetString();
      Printf("  %u. %s", i+1, s.Data());
    }

    TString ans = Getline("\nYour choice: ");
    UInt_t nAns = ans.Atoi();

    if ((nAns == 0) || (nAns > oa->GetEntries())) {
      Printf("Not valid");
    }
    else {
      os = (TObjString *)oa->At(nAns-1);
      simTag = os->GetString();
      break;
    }
  }

  // Ask for the cdbTag (automatically search in the simTag dir)
  TString cdbList = gSystem->GetFromPipe(
    Form("cd \"%s/%s\" ; find . -name 'mtracks-*.root' -not -name '*fulleff.root' | sort | cut -b11- | cut -d. -f1", anaDir.Data(), simTag.Data())
  );

  TString cdbTag;

  while (kTRUE) {

    Printf("\nChoose the type of efficiency for simulation %s\n", simTag.Data());

    TObjArray *oa = cdbList.Tokenize("\n\r");
    TObjString *os;
    TString s;
    for (UInt_t i=0; i<oa->GetEntries(); i++) {
      os = (TObjString *)oa->At(i);
      s = os->GetString();
      Printf("  %u. %s", i+1, s.Data());
    }

    TString ans = Getline("\nYour choice: ");
    UInt_t nAns = ans.Atoi();

    if ((nAns == 0) || (nAns > oa->GetEntries())) {
      Printf("Not valid");
    }
    else {
      os = (TObjString *)oa->At(nAns-1);
      cdbTag = os->GetString();
      break;
    }
  }

  // Run the analysis
  baseOut = Form("%s_%s", simTag.Data(), cdbTag.Data());
  TString prefix =  Form("%s/%s", anaDir.Data(), simTag.Data());
  CompareSingle(prefix, cdbTag);

}

////////////////////////////////////////////////////////////////////////////////
// Compares data for one value of cdb
////////////////////////////////////////////////////////////////////////////////
void CompareSingle(TString prefix, TString cdbTag) {

  cout << endl;
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  Printf("!! Analyzing data in %s", prefix.Data());
  Printf("!! Using fast/slow efficiency OCDB %s", cdbTag.Data());
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  cout << endl;

  TFile *effFull = TFile::Open(
    Form("%s/mtracks-%s-fulleff.root", prefix.Data(), cdbTag.Data())
  ); 
  TFile *effR    = TFile::Open(
    Form("%s/mtracks-%s.root", prefix.Data(), cdbTag.Data())
  );

  // Generated particles
  TTree *genFull = (TTree *)effFull->Get("muGen");
  TTree *genR    = (TTree *)effR->Get("muGen");

  // Reconstructed tracks
  TTree *recFull = (TTree *)effFull->Get("muRec");
  TTree *recR    = (TTree *)effR->Get("muRec");

  // Inits text output
  Echo(0x0, Form("%s.txt", baseOut.Data()));

  // Sets the global favorite ROOT style
  SetStyle();

  // Creates new objects in memory, not on files
  gROOT->cd();

  // Plots of generated data
  PlotsGen("full", "100%",   genFull);
  PlotsGen("slow", "R slow", genR, kRed, 26);
  PlotsGen();

  // Plots of reconstructed data
  PlotsRec("full", "100%",   recFull);
  PlotsRec("slow", "R slow", recR, kRed);
  PlotsRec("fast", "R fast", recFull, kMagenta, 0, kTRUE);
  PlotsRec();

  // Plots of matching results and more
  PlotsMatch("full", "100%",   genFull, recFull, kBlue);
  PlotsMatch("slow", "R slow", genR, recR, kRed, 26);
  PlotsMatch("fast", "R fast", genFull, recFull, kMagenta, 3, kTRUE);
  PlotsMatch();

  // Plots the difference of Rslow and Rfast
  PlotsRecDiff(kRed);

  // Percentages
  MatchPercentages();

  // Close files
  effFull->Close();
  effR->Close();
  Echo();

  cout << endl;
  Printf("Remember: to save the plots on files, use WritePlots()");

}

////////////////////////////////////////////////////////////////////////////////
// Difference of histograms. You may want to draw the absolute difference and
// you may want data to be normalized first
////////////////////////////////////////////////////////////////////////////////
TH1 *HistoDiff(TString diffName, TString name1, TString name2,
  Bool_t norm = kFALSE, Bool_t abs = kFALSE) {

  TH1 *h1 = (TH1 *)gROOT->FindObject(name1);
  TH1 *h2 = (TH1 *)gROOT->FindObject(name2);

  if ((h1 == 0x0) || (h2 == 0x0)) {
    Printf("Error: can't find at least one histogram");
    return 0x0;
  }

  // Number of bins
  UInt_t n = h1->GetNbinsX();
  Double_t e1 = h1->GetEntries();
  Double_t e2 = h2->GetEntries();

  // Output histogram
  TH1D *hDiff = new TH1D(diffName, diffName,
    n,
    h1->GetBinLowEdge(1),
    h1->GetBinLowEdge(n+1)
  );
  hDiff->GetXaxis()->SetTitle( h1->GetXaxis()->GetTitle() );
  hDiff->GetYaxis()->SetTitle( h1->GetYaxis()->GetTitle() );

  // Browse both histograms (we suppose they have the same number of bins)
  for (UInt_t i=1; i<=n; i++) {
    Double_t diff, v1, v2;
    v1 = h1->GetBinContent(i);
    v2 = h2->GetBinContent(i);
    if (norm) {
      v1 /= e1;
      v2 /= e2;
    }
    diff = v1-v2;
    if ((abs) && (diff < 0)) diff = -diff;

    hDiff->SetBinContent(i, diff);
  }

  // Returns the difference
  return hDiff;
}

////////////////////////////////////////////////////////////////////////////////
// Read the information from the Monte Carlo tree inside the file
////////////////////////////////////////////////////////////////////////////////
void PlotsRecDiff(Color_t color = kBlack, Style_t markerStyle = 0) {

  TCanvas *canvas = 0x0;
  TLegend *legend = 0x0;

  // This function is called for the first time: create canvas and legend
  canvas = new TCanvas("c_recdiff", "Difference of reconstructed slow/fast",
    800, 500);
  canvas->cd(0);
  canvas->Divide(3, 2);
  legend = StandardLegend();

  TString drawOpts = "HIST ";
  if (markerStyle) drawOpts = "P ";
  else drawOpts = "HIST ";

  // Variables shared by all histograms
  TString hName;
  TH1 *h;

  const Char_t *what[] = { "ptot", "pt", "phi", "theta", "dca", "rabs" };
  UInt_t n = sizeof(what) / sizeof(Char_t *);

  for (UInt_t i=0; i<n; i++) {
    canvas->cd(i+1);
    TString nDiff = Form("h_rec_%s_diff", what[i]);
    TString nSlow = Form("h_rec_%s_slow", what[i]);
    TString nFast = Form("h_rec_%s_fast", what[i]);
    h = HistoDiff(nDiff, nSlow, nFast, kTRUE /* norm */, kTRUE /* abs */);
    SetHistoStyle(h, markerStyle, color);
    h->Draw(drawOpts);

    if (i == 0) legend->AddEntry(h, "diff slow fast", (markerStyle ? "p" : "l"));
  }

  // Finalize
  canvas->cd(1);
  legend->Draw();

}

////////////////////////////////////////////////////////////////////////////////
// Read the information from the Monte Carlo tree inside the file
////////////////////////////////////////////////////////////////////////////////
void PlotsGen(TString tag = "", TString shortLabel = "", TTree *t = 0x0, 
  Color_t color = kBlack, Style_t markerStyle = 0) {

  static TCanvas *canvas = 0x0;
  static TLegend *legend = 0x0;
  static UInt_t nCalled = 0;

  // In this special mode, with only one parameter given, legend is drawn and 
  // canvas is saved to a pdf file
  if (t == 0x0) {
    for (UInt_t i=1; i<=8; i++) AutoScale( canvas->cd(i) );
    canvas->cd(1);
    legend->Draw();
    return;
  }

  TString drawOpts;

  // This function is called for the first time: create canvas and legend
  if (!canvas) {
    canvas = new TCanvas("c_gen", "Generated particles", 500, 800);
    canvas->cd(0);
    canvas->Divide(2, 4);
    legend = StandardLegend();
  }
  else {
    drawOpts = "SAME ";
  }

  if (markerStyle) drawOpts += "P ";
  else drawOpts += "HIST ";

  // Counter of canvas; 1 is the first canvas
  UInt_t cc = 0;

  // Increment number of times this function was called
  nCalled++;

  // Variables shared by all histograms
  TString hName;
  TH1 *h;

  // Rapidity
  canvas->cd(++cc);
  hName = Form("h_gen_rap_%s", tag.Data());
  t->Project(hName, "Rapidity(fTracks.Energy(),fTracks.Pz())");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Rapidity, y", "dN/dy [counts]");
  h->Draw(drawOpts);

  // For the legend (call here once after the first plot)
  legend->AddEntry(h, shortLabel, (markerStyle ? "p" : "l"));

  // Total momentum
  canvas->cd(++cc);
  hName = Form("h_gen_ptot_%s", tag.Data());
  t->Project(hName, "fTracks.P()");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "P [GeV/c]", "dN/dP [counts]");
  h->Draw(drawOpts);

  // Transverse momentum
  canvas->cd(++cc);
  hName = Form("h_gen_pt_%s", tag.Data());
  t->Project(hName, "fTracks.Pt()");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Pt [GeV/c]", "dN/dPt [counts]");
  h->Draw(drawOpts);

  // Phi [0.2Pi[
  canvas->cd(++cc);
  hName = Form("h_gen_phi_%s", tag.Data());
  t->Project(hName, "RadToDeg(fTracks.Phi())");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "#varphi [deg]", "dN/d#varphi [counts]");
  h->Draw(drawOpts);

  // Theta [-Pi.Pi[
  canvas->cd(++cc);
  hName = Form("h_gen_theta_%s", tag.Data());
  t->Project(hName, "RadToDeg(fTracks.Theta())");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "#theta [deg]", "dN/d#theta [counts]");
  h->Draw(drawOpts);

  // Radius
  canvas->cd(++cc);
  hName = Form("h_gen_rad_%s", tag.Data());
  t->Project(hName, "fTracks.R()");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "R [cm]", "dN/dR [counts]");
  h->Draw(drawOpts);

  // Charge
  canvas->cd(++cc);
  hName = Form("h_gen_charge_%s", tag.Data());
  t->Project(hName, "-sign(fTracks.GetPdgCode())");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Charge, Q [e]", "dN/dQ [counts]");
  h->Draw(drawOpts);

  // Z of vertex
  canvas->cd(++cc);
  hName = Form("h_gen_vz_%s", tag.Data());
  t->Project(hName, "fTracks.Vz()");
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Vz [cm]", "dN/dVz [counts]");
  h->Draw(drawOpts);

}

////////////////////////////////////////////////////////////////////////////////
// Read the information from the reconstructed muons tree
////////////////////////////////////////////////////////////////////////////////
void PlotsRec(TString tag = "", TString shortLabel = "", TTree *t = 0x0,
  Color_t color = kBlack, Style_t markerStyle = 0, Bool_t flagKept = kFALSE) {

  static TCanvas *canvas = 0x0;
  static TLegend *legend = 0x0;
  static UInt_t nCalled = 0;

  // Let's select only matched and kept tracks
  //const Char_t *cond = "fTracks.ContainTrackerData()==1";
  const Char_t *cond = (flagKept) ?
    ("( KeptMatch(fTracks.ContainTriggerData(), fTracks.ContainTrackerData(), fTracks.GetHitsPatternInTrigCh()) != 0 )") :
    ("( KeptMatch(fTracks.ContainTriggerData(), fTracks.ContainTrackerData(), -1) != 0 )");

  // In this special mode, with t = 0x0, legend is drawn and canvas is saved to
  // a pdf file
  if (t == 0x0) {
    for (UInt_t i=1; i<=8; i++) AutoScale( canvas->cd(i) );
    canvas->cd(1);
    legend->Draw();
    return;
  }

  TString drawOpts;

  // This function is called for the first time: create canvas and legend
  if (!canvas) {
    canvas = new TCanvas("c_rec", "Reconstructed matching particles", 500, 800);
    canvas->cd(0);
    canvas->Divide(2, 4);
    legend = StandardLegend();
  }
  else {
    drawOpts = "SAME ";
  }

  if (markerStyle) drawOpts += "P ";
  else drawOpts += "HIST ";

  // Counter of canvas; 1 is the first canvas
  UInt_t cc = 0;

  // Increment number of times this function was called
  nCalled++;

  // Variables shared by all histograms
  TString hName;
  TH1 *h;

  // Rapidity
  canvas->cd(++cc);
  hName = Form("h_rec_rap_%s", tag.Data());
  t->Project(hName, "Rapidity(fTracks.E(),fTracks.Pz())", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Rapidity, y", "dN/dy [counts]");
  h->Draw(drawOpts);

  // For the legend (call here once after the first plot)
  legend->AddEntry(h, shortLabel, (markerStyle ? "p" : "l"));

  // Total momentum
  canvas->cd(++cc);
  hName = Form("h_rec_ptot_%s", tag.Data());
  t->Project(hName, "fTracks.P()", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "P [GeV/c]", "dN/dP [counts]");
  h->Draw(drawOpts);

  // Transverse momentum
  canvas->cd(++cc);
  hName = Form("h_rec_pt_%s", tag.Data());
  t->Project(hName, "fTracks.Pt()", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Pt [GeV/c]", "dN/dPt [counts]");
  h->Draw(drawOpts);

  // Phi [0.2Pi[
  canvas->cd(++cc);
  hName = Form("h_rec_phi_%s", tag.Data());
  t->Project(hName, "RadToDeg(fTracks.Phi())", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "#varphi [deg]",
    "dN/d#varphi [counts]");
  h->Draw(drawOpts);

  // Theta [-Pi.Pi[
  canvas->cd(++cc);
  hName = Form("h_rec_theta_%s", tag.Data());
  t->Project(hName, "RadToDeg(fTracks.Theta())", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "#theta [deg]",
    "dN/d#theta [counts]");
  h->Draw(drawOpts);

  // DCA
  canvas->cd(++cc);
  hName = Form("h_rec_dca_%s", tag.Data());
  t->Project(hName, "fTracks.GetDCA()", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "DCA [cm]", "dN/dDCA [counts]");
  h->Draw(drawOpts);

  // R at the end of the absorber
  canvas->cd(++cc);
  hName = Form("h_rec_rabs_%s", tag.Data());
  t->Project(hName, "fTracks.GetRAtAbsorberEnd()", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "R_{abs} [cm]", "dN/dRabs [counts]");
  h->Draw(drawOpts);

  // Associated MC particle label
  canvas->cd(++cc);
  hName = Form("h_rec_assmc_%s", tag.Data());
  //h = new TH1I(hName, hName, 13, -2.5, 10.5);
  t->Project(hName, "fTracks.GetLabel()", cond);
  gDirectory->GetObject(hName, h);
  SetHistoStyle(h, markerStyle, color, "Associated MC label",
    "dN/dMCLabel [counts]");
  h->Draw(drawOpts);

}

////////////////////////////////////////////////////////////////////////////////
// Read the information from both reconstructed and generated trees to compare
// the number of particles generated and reconstructed for each event, the match
// trigger information for rec and which tracks are in tracker, trigger or both
////////////////////////////////////////////////////////////////////////////////
void PlotsMatch(TString tag = "", TString shortLabel = "", TTree *tg = 0x0,
  TTree *tr = 0x0, Color_t color = kBlack, Style_t markerStyle = 0,
  Bool_t flagKept = kFALSE) {

  static TCanvas *canvas = 0x0;
  static TLegend *legend = 0x0;
  static UInt_t nCalled = 0;

  // In this special mode, with only one parameter given, legend is drawn and 
  // canvas is saved to a pdf file
  if (tg == 0x0) {
    for (UInt_t i=1; i<=4; i++) AutoScale( canvas->cd(i) );
    canvas->cd(3);
    legend->Draw();
    return;
  }

  TString drawOpts;

  // This function is called for the first time: create canvas and legend
  if (!canvas) {
    canvas = new TCanvas("c_match", "Generated events and matching info",
      500, 400);
    canvas->cd(0);
    canvas->Divide(2, 2);
    legend = StandardLegend();
  }
  else {
    drawOpts += "SAME ";
  }

  if (markerStyle) {
    drawOpts += "P ";
  }

  // Variables shared by all histograms
  TString hName;
  TH1 *h;

  // Counter of canvas; 1 is the first canvas
  UInt_t cc = 0;

  // Increment number of times this function was called
  nCalled++;

  if (!flagKept) {

    // Generated multiplicity
    canvas->cd(++cc);
    hName = Form("h_match_multgen_%s", tag.Data());
    tg->Project(hName, "@fTracks.size()");
    gDirectory->GetObject(hName, h);
    SetHistoStyle(h, markerStyle, color, "Num. gen tracks per event",
      "dN/dNTrEv [counts]", "", kTRUE);
    h->Draw(drawOpts);

    // Reconstructed multiplicity
    canvas->cd(++cc);
    hName = Form("h_match_multrec_%s", tag.Data());
    tr->Project(hName, "@fTracks.size()");
    gDirectory->GetObject(hName, h);
    SetHistoStyle(h, markerStyle, color, "Num. total rec tracks per event",
      "dN/dNTrEv [counts]", "");
    h->Draw(drawOpts);

  }
  else {
    cc += 2;
  }

  // Trigger match on reconstructed tracks
  canvas->cd(++cc);
  hName = Form("h_match_trigmatch_%s", tag.Data());
  h = new TH1I(hName, hName, 4, -0.5, 3.5);
  h->GetXaxis()->SetBinLabel(1, "no trig match");  // GetMatchTrigger()=0
  h->GetXaxis()->SetBinLabel(2, "below pt cut");   // GetMatchTrigger()=1
  h->GetXaxis()->SetBinLabel(3, "match low pt");   // GetMatchTrigger()=2
  h->GetXaxis()->SetBinLabel(4, "match high pt");  // GetMatchTrigger()=3

  if (flagKept) {
    tr->Project(
      hName,
      "MtGetMatchTrigger(fTracks.GetMatchTrigger(), fTracks.GetHitsPatternInTrigCh())",
      "( Kept( fTracks.ContainTriggerData(), fTracks.ContainTrackerData(), fTracks.GetHitsPatternInTrigCh()) != 0 )"
    );
  }
  else {
    tr->Project(hName, "fTracks.GetMatchTrigger()");
  }

  SetHistoStyle(h, markerStyle, color, "Match trigger cuts",
    "dN/dMatch [counts]", "");
  h->Draw(drawOpts);

  // For the legend (call here once after only one plot)
  legend->AddEntry(h, shortLabel, (markerStyle ? "p" : "l"));

  Double_t fracMatch =
    ( h->GetBinContent(2) + h->GetBinContent(3) + h->GetBinContent(4) ) /
    (Double_t)h->GetEntries();
  PrintHisto(h, shortLabel, 0);
  Echo(Form(">> %-20s : %11.4f", "match_trig/tot_rec", fracMatch*100.));

  // Tracks that have trigger, tracker or both information
  canvas->cd(++cc);

  hName = Form("h_match_trigtrack_%s", tag.Data());
  h = new TH1I(hName, hName, 3, 0.5, 3.5);
  h->GetXaxis()->SetBinLabel(1, "only trigger");   // TrigTrack()=1
  h->GetXaxis()->SetBinLabel(2, "only tracker");   // TrigTrack()=2
  h->GetXaxis()->SetBinLabel(3, "matched");        // TrigTrack()=3

  if (flagKept) {
    tr->Project(hName,
      "TrigTrack(fTracks.ContainTriggerData(),fTracks.ContainTrackerData(),fTracks.GetHitsPatternInTrigCh())",
      "( Kept( fTracks.ContainTriggerData(), fTracks.ContainTrackerData(), fTracks.GetHitsPatternInTrigCh()) != 0 )"
    );
  }
  else {
    tr->Project(hName, "TrigTrack(fTracks.ContainTriggerData(),"
      "fTracks.ContainTrackerData())");
  }

  SetHistoStyle(h, markerStyle, color, "Match trigger/tracker",
    "dN/dMatch [counts]", "");
  h->Draw(drawOpts);
  PrintHisto(h, shortLabel, 0);

}

////////////////////////////////////////////////////////////////////////////////
// Sets the style of the histogram
////////////////////////////////////////////////////////////////////////////////
void SetHistoStyle(TH1 *h, Style_t markerStyle, Color_t color,
  TString xLabel = "", TString yLabel = "", TString title = "",
  Bool_t stats = kFALSE) {

  if (markerStyle == 999) h->SetMarkerSize(3.);  // 999 = TEXT
  else h->SetMarkerStyle(markerStyle);

  if (markerStyle) h->SetMarkerColor(color);
  else h->SetLineColor(color);

  h->SetTitle(title);
  if (!xLabel.IsNull()) h->GetXaxis()->SetTitle(xLabel);
  if (!yLabel.IsNull()) h->GetYaxis()->SetTitle(yLabel);

  h->GetYaxis()->SetTitleOffset(2.00);
  h->SetStats(stats);
  gPad->SetLeftMargin(0.17);

}

////////////////////////////////////////////////////////////////////////////////
// Sets the global style of ROOT
////////////////////////////////////////////////////////////////////////////////
void SetStyle() {
  gROOT->SetStyle("Plain");
  gStyle->SetOptStat("e");
}

////////////////////////////////////////////////////////////////////////////////
// Creates the TLegend for all with same coordinates
////////////////////////////////////////////////////////////////////////////////
TLegend *StandardLegend() {
  //TLegend *legend = new TLegend(0.136, 0.644, 0.464, 0.886);
  TLegend *legend = new TLegend(0.176, 0.644, 0.484, 0.886);
  legend->SetFillStyle(0);
  legend->SetShadowColor(0);
  legend->SetBorderSize(0);
  return legend;
}

////////////////////////////////////////////////////////////////////////////////
// Prints every bin of the histogram, with proper bin label, if available
////////////////////////////////////////////////////////////////////////////////
void PrintHisto(TH1 *h, TString header, UInt_t dec = 2, UInt_t integ = 6) {

  Char_t *title;

  if (*(h->GetTitle()) != '\0') title = h->GetTitle();
  else title = h->GetXaxis()->GetTitle();

  Echo(Form("\n==== [%s] %s ====", header.Data(), title));

  // ">> % 20.4lf : %11.4f"
  UInt_t tot = integ+dec+1;
  if (dec == 0) tot--;
  TString fmt_num = Form(">> %% 20.4lf : %%%u.%ulf", tot, dec);
  TString fmt_lab = Form(">> %%-20s : %%%u.%ulf", tot, dec);

  Echo(Form(">> %-20s : %6.0lf", "** ENTRIES **", h->GetEntries()));

  for (Int_t i=1; i<=h->GetNbinsX(); i++) {
    const char *binLabel = h->GetXaxis()->GetBinLabel(i);
    if ((binLabel == 0x0) || (*binLabel == '\0')) {
      // Without label, use bin value
      Echo(Form(fmt_num.Data(),
        h->GetBinCenter(i),
        h->GetBinContent(i)
      ));
    }
    else {
      // With label
      Echo(Form(fmt_lab.Data(),
        h->GetXaxis()->GetBinLabel(i),
        h->GetBinContent(i)
      ));
    }
  }

}

////////////////////////////////////////////////////////////////////////////////
// Calculate percentages
////////////////////////////////////////////////////////////////////////////////
void MatchPercentages() {

  TH1 *h100  = gDirectory->Get("h_match_trigmatch_full");
  TH1 *hSlow = gDirectory->Get("h_match_trigmatch_slow");
  TH1 *hFast = gDirectory->Get("h_match_trigmatch_fast");

  Float_t match100Norm  = (h100->GetEntries()  - h100->GetBinContent(1))  / h100->GetEntries();
  Float_t matchSlowNorm = (hSlow->GetEntries() - hSlow->GetBinContent(1)) / hSlow->GetEntries();
  Float_t matchFastNorm = (hFast->GetEntries() - hFast->GetBinContent(1)) / hFast->GetEntries();

  // MTR-Eff values
  Float_t mtrEffSlow = matchSlowNorm/match100Norm;
  Float_t mtrEffFast = matchFastNorm/match100Norm;

  // R values as if they were actually only one value -- we need to solve an
  // equation!
  Float_t rAvgSlow, rAvgFast;

  for (UInt_t i=0; i<2; i++) {
    Double_t mtrEff;

    TF1 f("rToEff", "4*x^3-3*x^4-[0]");

    if (i==0) f.SetParameter(0, mtrEffSlow);
    else      f.SetParameter(0, mtrEffFast);

    ROOT::Math::WrappedTF1 wf1(f);
    ROOT::Math::BrentRootFinder brf;
    brf.SetFunction(wf1, 0, 1);
    brf.Solve();

    if (i==0) rAvgSlow = brf.Root();
    else      rAvgFast = brf.Root();
  }

  Echo("");
  Echo(Form("*** MATCHED TRACKS ***"));
  Echo(Form("slow | MTR-Eff = %7.4f %% | R-avg = %7.4f %%", 100.*mtrEffSlow, 100.*rAvgSlow));
  Echo(Form("fast | MTR-Eff = %7.4f %% | R-avg = %7.4f %%", 100.*mtrEffFast, 100.*rAvgFast));
  Echo(Form("diff | MTR-Eff = %7.4f %% | R-avg = %7.4f %%", 100.*TMath::Abs(mtrEffFast-mtrEffSlow), 100.*TMath::Abs(rAvgFast-rAvgSlow)));

}

////////////////////////////////////////////////////////////////////////////////
// Calculates rapidity from E and Pz. It's even usable in varexp!!!
////////////////////////////////////////////////////////////////////////////////
Double_t Rapidity(Double_t e, Double_t pz) {
  Double_t rap;
  if (e != pz) {
    rap = 0.5*TMath::Log((e+pz)/(e-pz));
  }
  else {
    rap = -200;
  }
  return rap;
}

////////////////////////////////////////////////////////////////////////////////
// Radians to degrees
////////////////////////////////////////////////////////////////////////////////
Double_t RadToDeg(Double_t rad) {
  return 180.*rad/TMath::Pi();
}

////////////////////////////////////////////////////////////////////////////////
// Calcluates a numeric value named TrigTrack that indicates if:
//  1 : track is in trigger only
//  2 : track is in tracker only
//  3 : track matched (both trigger and tracker)
////////////////////////////////////////////////////////////////////////////////
UInt_t TrigTrack(Bool_t trig, Bool_t track, Int_t flag = -1) {

  UInt_t tt = 0;

  if ((trig) && (!track))      tt = 1;
  else if ((!trig) && (track)) tt = 2;
  else if ((trig) && (track))  tt = 3;

  if (flag != -1) {
    Bool_t kept = MtIsKept(flag);
    if (!kept) {
      if (tt == 3) tt = 2;
      else if (tt == 1) tt = 0;
    }
  }

  return tt;

}

////////////////////////////////////////////////////////////////////////////////
// Returns kTRUE if the track has been kept by the algo; flag must be the return
// value of AliESDMuonTrack::GetHitsPatternInTrigCh()
////////////////////////////////////////////////////////////////////////////////
Bool_t MtIsKept(UShort_t flag) {
  return ((flag & 0x8000) != 0);
}

////////////////////////////////////////////////////////////////////////////////
// Decides to count a track only if it matches both trigger and tracker and it
// was kept by the algo
////////////////////////////////////////////////////////////////////////////////
Bool_t KeptMatch(Bool_t trig, Bool_t track, Int_t flag = -1) {

  // kept and matches
  if (((trig) && (track)) && ((flag == -1) || (flag & 0x8000)))
    return kTRUE;

  // any other case
  return kFALSE;

}

////////////////////////////////////////////////////////////////////////////////
// If track was triggeronly and not kept, discard it
////////////////////////////////////////////////////////////////////////////////
Bool_t Kept(Bool_t trig, Bool_t track, Int_t flag) {

  if (flag & 0x8000) return kTRUE;        // consider kept tracks
  if ((trig) && (!track)) return kFALSE;  // discard trigger only
  return kTRUE;                           // consider match or tracker

}

////////////////////////////////////////////////////////////////////////////////
// GetMatchTrigger(): corrected value for "kept" flag
////////////////////////////////////////////////////////////////////////////////
UInt_t MtGetMatchTrigger(UShort_t match, UShort_t kept = kTRUE) {
  if (MtIsKept(kept)) return match;
  return 0;
}

////////////////////////////////////////////////////////////////////////////////
// Echo line on an output file and on the screen at the same time
////////////////////////////////////////////////////////////////////////////////
void Echo(const Char_t *s = 0x0, const Char_t *f = 0x0) {
  static ofstream os;
  if (s == 0) {
    if (f == 0) os.close();
    else os.open(f);
  }
  else {
    cout << s << endl;
    os << s << endl;
  }
}

////////////////////////////////////////////////////////////////////////////////
// Auto scale function to fit all the different y scales of the histograms on a
// given canvas!
////////////////////////////////////////////////////////////////////////////////
void AutoScale(TVirtualPad *can) {

  // Get the list of contents of that canvas
  TList *l = can->GetListOfPrimitives();
  TIter it(l);
  TObject *o;

  TH1 *hFirst = 0x0;
  TH1 *h = 0x0;
  Double_t ymin, ymax;

  // Browse content (may be any class)
  while (( o = it.Next() )) {
    cl = TClass::GetClass(o->ClassName());

    // Consider only histograms
    if (cl->InheritsFrom(TH1::Class())) {
      h = (TH1 *)o;
      if (hFirst == 0x0) {
        hFirst = h;
        ymin = hFirst->GetMinimum();
        ymax = hFirst->GetMaximum();
      }
      else {
        ymin = TMath::Min(ymin, h->GetMinimum());
        ymax = TMath::Max(ymax, h->GetMaximum());
      }
    }
  }

  // Apply changes to the first histogram (which beholds the axis)
  if (hFirst) {
    Double_t f = 0.1;  // 10%

    // Like this, we leave empty the 100.*f % of the future size of the canvas
    // (umax - ymin). If one of ymax or ymin is zero, leave no space for it

    Double_t umax, umin;

    if (ymin == 0) {
      umax = (ymax - f*ymin) / (1.-f);
      umin = 0.;
    }
    else if (ymax == 0) {
      umax = 0.;
      umin = (ymin - f*ymax) / (1.-f);
    }
    else {
      umax = ( f*ymin + (f-1.)*ymax ) / (2.*f-1.);
      umin = ( f*(ymax+ymin) - ymin ) / (2.*f-1.);
    }

    //Printf("----> hname=%s min=%.2f max=%.2f", hFirst->GetName(), ymin, ymax);
    hFirst->GetYaxis()->SetRangeUser(umin, umax);
    can->Modified();
  }

}

////////////////////////////////////////////////////////////////////////////////
// Creates files from canvases in the desired format (default: pdf)
////////////////////////////////////////////////////////////////////////////////
void WritePlots(TString fmt = "pdf",
  TString what = "c_gen c_rec c_match c_recdiff") {

  // ROOT pdf generation *sucks*: create eps then convert to pdf
  Bool_t pdf = kFALSE;
  if (fmt == "pdf") {
    pdf = kTRUE;
    fmt = "eps";
  }

  TObjArray *oa = what.Tokenize(" ");
  for (Int_t i=0; i<oa->GetEntries(); i++) {
    TString s = ((TObjString *)oa->At(i))->GetString();
    TCanvas *c = gROOT->FindObject(s);
    if (c != 0x0) {
      TString out = Form("%s_%s.%s",
        baseOut.Data(),
        s(2, s.Length()).Data(),
        fmt.Data()
      );
      c->Print(out);
      if (pdf) {
        Printf("Converting to pdf...");
        gSystem->Exec(Form("epstopdf %s && rm -f %s", out.Data(), out.Data()));
      }
    }
    else {
      Printf("Warning: can't find TCanvas %s", s.Data());
    }
  }
}
