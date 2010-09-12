void Trig4434(TString bn) {

  gROOT->SetStyle("Plain");

  //TFile *f = TFile::Open("mtracks-r-maxcorr.root");
  TFile *f = TFile::Open(
    Form("/Users/volpe/Desktop/mtracks-%s.root", bn.Data())
  );
  if (!f) {
    Printf("Can't open file");
    return;
  }

  TList *l = f->Get("histos");
  if (!l) {
    Printf("Can't get list of histograms");
    f->Close();
    delete f;
    return;
  }

  TH1 *hb = l->FindObject("h4434b");
  TH1 *hn = l->FindObject("h4434n");

  if ((!hb) || (!hn)) {
    Printf("Can't find histograms inside list");
    f->Close();
    delete f;
  }

  // Here we have the histos
  hb->SetStats(kFALSE);
  hn->SetStats(kFALSE);

  TCanvas *c = new TCanvas("c4434", "4/4 vs. 3/4 triggers", 600, 400);
  c->Divide(2, 1);

  c->cd(1);
  SetStyle(hb, kRed);
  hb->Draw();
  //AutoScale(gPad);

  c->cd(2);
  SetStyle(hn, kBlue);
  hn->Draw();
  //AutoScale(gPad);

  c->cd(0);
  c->Print(
    Form(
      "%s/%s.eps",
      gSystem->DirName(f->GetName()),
      bn.Data()
    )
  );
  gSystem->Exec(
    Form(
      "epstopdf %s/%s.eps && rm %s/%s.eps",
      gSystem->DirName(f->GetName()),
      bn.Data(),
      gSystem->DirName(f->GetName()),
      bn.Data()
    )
  );

  f->Close();
  delete f;

}

////////////////////////////////////////////////////////////////////////////////
// Common histo styles
////////////////////////////////////////////////////////////////////////////////
void SetStyle(TH1 *h, Color_t col) {
  h->GetYaxis()->SetTitleOffset(2.00);
  h->SetStats(kFALSE);
  h->Scale( 100./h->GetEntries() );
  h->GetYaxis()->SetTitle("triggered tracks [%]");
  h->SetLineColor(col);
  gPad->SetLeftMargin(0.17);
  h->GetYaxis()->SetRangeUser(0., 105.);
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
