void sim(Int_t nev=500) {

  AliSimulation MuonSim;
  MuonSim.SetTriggerConfig("MUON");
  MuonSim.SetMakeSDigits("MUON");
  MuonSim.SetMakeDigits("MUON");
  MuonSim.SetRunHLT("");
  MuonSim.SetRunQA(":");
  
  MuonSim.SetDefaultStorage("local://$ALICE_ROOT/OCDB"); 
  
  // GRP
  MuonSim.SetSpecificStorage("GRP/GRP/Data",Form("local://%s",gSystem->pwd()));
  
  TStopwatch timer;
  timer.Start();
  
  MuonSim.Run(nev);
  
  timer.Stop();
  timer.Print();
  
}
