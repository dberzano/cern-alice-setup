void sim(Int_t nev) {

  AliSimulation MuonSim;
  MuonSim.SetTriggerConfig("MUON");
  MuonSim.SetMakeSDigits("MUON");
  MuonSim.SetMakeDigits("MUON");
  MuonSim.SetRunHLT("");
  MuonSim.SetRunQA(":");
  
  MuonSim.SetDefaultStorage("local://$ALICE_ROOT/OCDB"); 
  
  // GRP
  MuonSim.SetSpecificStorage( "GRP/GRP/Data",
    Form("local://%s", gSystem->pwd()));

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

  TStopwatch timer;
  timer.Start();
  
  MuonSim.Run(nev);
  
  timer.Stop();
  timer.Print();
 
}
