////////////////////////////////////////////////////////////////////////////////
// Makes OCDB for muon trigger efficiency cells starting from a text file. Watch
// out: it only works until revision 41033 of AliRoot!
//
// by Dario Berzano <dario.berzano@gmail.com>
////////////////////////////////////////////////////////////////////////////////
void MakeCdbFromDat() {

  cout << endl;
  cout << "==== Include path ====" << endl;
  cout << gSystem->GetIncludePath() << endl;
  cout << endl;

  AliMUONTriggerEfficiencyCells *ec =
    AliMUONTriggerEfficiencyCells("efficiencyCells-50pct.dat");

  AliCDBManager *cdb = AliCDBManager::Instance();
  cdb->SetDefaultStorage(Form("local:///%s/../cdb/50eff/", gSystem->pwd()));

  // CDB ID
  AliCDBId id;
  id.SetPath("MUON/Calib/TriggerEfficiency");
  id.SetFirstRun(0);
  id.SetLastRun(999999999);
  id.SetVersion(0);
  id.SetSubVersion(0);

  // Meta data
  AliCDBMetaData *meta = new AliCDBMetaData();
  meta->SetComment("MTR with 50% efficiency per local board");

  // Assemble into one CDB entry
  cdb->Put( (TObject *)ec, id, meta );

}
