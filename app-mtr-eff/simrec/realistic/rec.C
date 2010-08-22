void rec() {

  AliCDBManager* man = AliCDBManager::Instance();
  man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");

  AliReconstruction MuonRec; 

  // Turn off the QA (Dario)
  MuonRec.SetRunQA(":");

  MuonRec.SetInput("raw.root");
  MuonRec.SetRunVertexFinder(kTRUE);
  MuonRec.SetRunLocalReconstruction("MUON ITS");
  MuonRec.SetRunTracking("MUON");
  MuonRec.SetFillESD("MUON");
  MuonRec.SetLoadAlignData("MUON");
  MuonRec.SetNumberOfEventsPerFile(1000);
  //MuonRec.SetOption("MUON", recoptions);

  MuonRec.SetDefaultStorage("local://$ALICE_ROOT/OCDB");

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

  // GRP
  MuonRec.SetSpecificStorage("GRP/GRP/Data",Form("local://%s",gSystem->pwd()));  
  TStopwatch timer;
  timer.Start();
  MuonRec.Run();
  timer.Stop();
  timer.Print();
}
