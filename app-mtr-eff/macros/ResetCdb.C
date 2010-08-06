void ResetCdb(TString inCdb, TString comment = "") {

  // Extract the OCDB from the following file
  TFile *f = TFile::Open(inCdb);
  AliCDBEntry *e = (AliCDBEntry*)f->Get("AliCDBEntry");
  AliCDBManager *cdb = AliCDBManager::Instance();

  gSystem->mkdir("cdb_out");
  cdb->SetDefaultStorage( Form("local://%s/cdb_out", gSystem->pwd()) );

  e->GetId().SetFirstRun(0);
  e->GetId().SetLastRun(999999999);
  e->GetId().SetVersion(0);
  e->GetId().SetSubVersion(0);

  Printf("\n==== Before adding comment ====");
  e->PrintMetaData();

  // Append the new comment
  if (!comment.IsNull()) {
    TString oldComment = e->GetMetaData()->GetComment();
    comment = oldComment + " " + comment;
    e->GetMetaData()->SetComment(comment);
  }

  Printf("\n==== After adding comment ====");
  e->PrintMetaData();

  // Dumps reconditioned OCDB onto the destpath
  cdb->Put(e);

  f->Close();
  delete f;
}
