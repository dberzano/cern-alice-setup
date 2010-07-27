void rec() {

  AliReconstruction MuonRec;

  MuonRec.SetRunLocalReconstruction("MUON");
  MuonRec.SetRunTracking("MUON");
  MuonRec.SetRunVertexFinder(kFALSE);
  MuonRec.SetFillESD("MUON");
  MuonRec.SetRunQA(":");
  
  MuonRec.SetDefaultStorage("local://$ALICE_ROOT/OCDB");

  // GRP
  MuonRec.SetSpecificStorage("GRP/GRP/Data",Form("local://%s",gSystem->pwd()));
  
  TStopwatch timer;
  timer.Start();
  MuonRec.Run();
  timer.Stop();
  timer.Print();
  
}
