void sim(Int_t nev) {

  AliSimulation MuonSim("Config.C");

  // Turn off the QA (Dario)
  MuonSim.SetRunQA(":");

  MuonSim.SetTriggerConfig("MUON");
  MuonSim.SetMakeSDigits("MUON ITS");
  MuonSim.SetMakeDigits("MUON ITS");
  MuonSim.SetMakeDigitsFromHits("");
  MuonSim.SetWriteRawData("MUON", "raw.root", kTRUE);
  
  MuonSim.SetDefaultStorage("local://$ALICE_ROOT/OCDB");   

  // Efficiency values are stored into OCDB
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  const char *mtrCdb = gSystem->Getenv("ALI_MTR_CDB");
  if ((mtrCdb) && (strcmp(mtrCdb, "") != 0)) {

    Printf("I'm setting the specific storage for SIM: %s", mtrCdb);
    MuonSim.SetSpecificStorage("MUON/Calib/TriggerEfficiency", mtrCdb);
  }
  else {
    Printf("WARNING: specific OCDB storage for MTR not set!");
  }
  Printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");

  // GRP
  MuonSim.SetSpecificStorage("GRP/GRP/Data",Form("local://%s",gSystem->pwd()));
  
  TStopwatch timer;
  timer.Start();
  MuonSim.Run(nev);
  timer.Stop();
  timer.Print();
}
