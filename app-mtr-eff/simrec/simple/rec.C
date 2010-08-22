void rec() {

  AliReconstruction MuonRec;

  MuonRec.SetRunLocalReconstruction("MUON");
  MuonRec.SetRunTracking("MUON");
  MuonRec.SetRunVertexFinder(kFALSE);
  MuonRec.SetFillESD("MUON");
  MuonRec.SetRunQA(":");
  
  MuonRec.SetDefaultStorage("local://$ALICE_ROOT/OCDB");

  // GRP
  MuonRec.SetSpecificStorage( "GRP/GRP/Data",
    Form("local://%s", gSystem->pwd()) );

  // Efficiency values are stored into OCDB
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  const char *mtrCdb = gSystem->Getenv("ALI_MTR_CDB");
  if ((mtrCdb) && (strcmp(mtrCdb, "") != 0)) {

    Printf("I'm setting the specific storage for REC: %s", mtrCdb);
    MuonRec.SetSpecificStorage("MUON/Calib/TriggerEfficiency", mtrCdb);
  }
  else {
    Printf("WARNING: specific OCDB storage for MTR not set!");
  }
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  
  TStopwatch timer;
  timer.Start();
  MuonRec.Run();
  timer.Stop();
  timer.Print();
  
}
