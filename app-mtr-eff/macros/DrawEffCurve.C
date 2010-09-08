void DrawEffCurve() {

  gROOT->SetStyle("Plain");

  TH1F *hRpcEff = new TH1F("hRpcEff", "", 1000, 0., 1);
  TH1F *hMtrEff = new TH1F("hMtrEff", "", 1000, 0., 1);

  UInt_t nBins = hRpcEff->GetNbinsX();

  for (UInt_t i=0; i<nBins; i++) {
    Float_t x = hRpcEff->GetBinCenter(i);
    Float_t e = x*x*x*x + 4.*(1.-x)*x*x*x;
    hRpcEff->SetBinContent(i, x);
    hMtrEff->SetBinContent(i, e);
  }

  TLegend *l = new TLegend(0.1551724, 0.6673729, 0.3520115, 0.8601695);
  l->AddEntry(hRpcEff, "RPC eff");
  l->AddEntry(hMtrEff, "MTR eff");
  l->SetFillStyle(0);

  hRpcEff->SetStats(kFALSE);
  hRpcEff->SetTitle("MTR efficiency and RPC efficiency");
  hRpcEff->SetLineColor(kBlue);
  hRpcEff->GetXaxis()->SetTitle("RPC eff");

  hMtrEff->SetLineColor(kRed);

  hRpcEff->Draw();
  hMtrEff->Draw("same");

  l->Draw();

}
