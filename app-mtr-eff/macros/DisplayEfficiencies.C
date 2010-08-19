////////////////////////////////////////////////////////////////////////////////
//
// DisplayEfficiencies.C -- by Dario Berzano <dario.berzano@gmail.com>
//
// Displays the efficiencies of the muon trigger per local board in the
// specified OCDB in a simple, uncluttered histogram.
//
////////////////////////////////////////////////////////////////////////////////
void DisplayEfficiencies(TString input, Int_t run = -1, Bool_t simple = kTRUE) {

  AliMUONTriggerEfficiencyCells *effCells = 0x0;
  AliMUONTriggerChamberEfficiency *eff = 0x0;

  if (run < 0) {
    // We are in mode "ROOT file"
    effCells = new AliMUONTriggerEfficiencyCells(input, "TrigChEff");
  }
  else {

    // We are in mode "OCDB"
    AliCDBManager *man = AliCDBManager::Instance();  
    man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");
    man->SetSpecificStorage("MUON/Calib/TriggerEfficiency", input);
    man->SetRun(run);

    AliCDBEntry *entry;
    entry = man->Get("MUON/Calib/TriggerEfficiency");

    entry->PrintMetaData();
    entry->GetId().Print();

    effCells = (AliMUONTriggerEfficiencyCells *)entry->GetObject();

  }

  // Get the efficiency handler
  if (!effCells) {
    Printf("Error while creating the efficiency cells, aborting");
    return;
  }
  eff = new AliMUONTriggerChamberEfficiency(effCells);

  // Set my style
  SetStyle();

  if (!simple) {
    // Use Diego's machinery
    eff->DisplayEfficiency();
  }
  else {

    // Use simpler 1D histograms

    // Canvases
    TCanvas *cBend = new TCanvas("cBend",
      "Efficiencies on bending plane", 500, 500);
    cBend->Divide(2, 2);

    TCanvas *cNonBend = new TCanvas("cNonBend",
      "Efficiencies on nonbending plane", 500, 500);
    cNonBend->Divide(2, 2);

    TCanvas *cBoth = new TCanvas("cBoth",
      "Efficiencies on both planes (correlation)", 500, 500);
    cBoth->Divide(2, 2);

    TH1F *hBend[4];
    TH1F *hNonBend[4];
    TH1F *hBoth[4];

    for (Int_t i=0; i<4; i++) {
      Int_t detElemId = 1000+100*(i+1);

      hBend[i] = new TH1F(Form("hEffBend_%d", i),
        Form("Trigger chamber %d", i+1), 234, 0.5, 234.5);

      hNonBend[i] = new TH1F(Form("hEffNonBend_%d", i),
        Form("Trigger chamber %d", i+1), 234, 0.5, 234.5);

      hBoth[i] = new TH1F(Form("hEffBoth_%d", i),
        Form("Trigger chamber %d", i+1), 234, 0.5, 234.5);

      for (Int_t j=1; j<=234; j++) {
        hBend[i]->SetBinContent(j, eff->GetCellEfficiency(detElemId, j,
          AliMUONTriggerEfficiencyCells::kBendingEff));
        hNonBend[i]->SetBinContent(j, eff->GetCellEfficiency(detElemId, j,
          AliMUONTriggerEfficiencyCells::kBendingEff));
        hBoth[i]->SetBinContent(j, eff->GetCellEfficiency(detElemId, j,
          AliMUONTriggerEfficiencyCells::kBothPlanesEff));
      }

      cBend->cd(i+1);
      SetHistoStyle(hBend[i], 0, kBlue, "Local board", "Efficiency", 0., 1.2);
      hBend[i]->Draw();

      cNonBend->cd(i+1);
      SetHistoStyle(hNonBend[i], 0, kBlue, "Local board", "Efficiency", 0., 1.2);
      hNonBend[i]->Draw();

      cBoth->cd(i+1);
      SetHistoStyle(hBoth[i], 0, kBlue, "Local board", "Efficiency", 0., 1.2);
      hBoth[i]->Draw();
    }

    cBend->cd(0);
    cNonBend->cd(0);
    cBoth->cd(0);
  }

}

////////////////////////////////////////////////////////////////////////////////
// Sets the style of the histogram
////////////////////////////////////////////////////////////////////////////////
void SetHistoStyle(TH1 *h, Style_t markerStyle, Color_t color,
  TString xLabel, TString yLabel, Double_t min = 0., Double_t max = 0.,
  TString title = "", Bool_t stats = kFALSE) {

  h->SetMarkerStyle(markerStyle);
  if (markerStyle != 0) {
    h->SetMarkerColor(color);
  }
  else {
    h->SetLineColor(color);
  }
  h->SetTitle(title);
  h->GetXaxis()->SetTitle(xLabel);
  h->GetYaxis()->SetTitle(yLabel);
  h->GetYaxis()->SetTitleOffset(1.5);
  h->SetStats(stats);
  gPad->SetLeftMargin(0.13);

  if (min != max) {
    h->SetMinimum(min);
    h->SetMaximum(max);
  }
}

////////////////////////////////////////////////////////////////////////////////
// Sets the global style of ROOT
////////////////////////////////////////////////////////////////////////////////
void SetStyle() {
  gROOT->SetStyle("Plain");
  gStyle->SetOptStat("e");
}
