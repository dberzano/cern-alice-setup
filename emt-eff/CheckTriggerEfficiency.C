void CheckTriggerEfficiency(Int_t run = 116380) {

  //printf("*** Connect to AliEn ***\n");
  //TGrid::Connect("alien://");

  AliCDBManager *man = AliCDBManager::Instance();
  
  man->SetDefaultStorage("local://$ALICE_ROOT/OCDB");

  man->SetSpecificStorage("MUON/Calib/TriggerEfficiency",
    Form("local://%s/OCDB", gSystem->pwd()));

  //man->SetSpecificStorage("MUON/Calib/TriggerEfficiency","alien://Folder=/alice/data/2010/OCDB");

  man->SetRun(run);

  //AliMUONTriggerDisplay *disp = new AliMUONTriggerDisplay();
  //disp->GetBoardNumberHisto("boards")->Draw("COLZ");

  AliCDBEntry *entry;
  entry = man->Get("MUON/Calib/TriggerEfficiency");

  AliCDBMetaData *md = entry->GetMetaData();
  cout << md->GetAliRootVersion() << endl;
  cout << md->GetComment() << endl;
  cout << md->GetResponsible() << endl;

  AliCDBId& id = entry->GetId();
  cout << "v" << id.GetVersion() << "  s" << id.GetSubVersion() << endl;
  cout << "Run " << id.GetFirstRun() << "   " << id.GetLastRun() << endl;

  TObject *obj = entry->GetObject();
  printf("Contains an object %s \n",obj->IsA()->GetName());

  AliMUONTriggerEfficiencyCells *e =
    dynamic_cast<AliMUONTriggerEfficiencyCells*>( obj );

  AliMUONTriggerChamberEfficiency *eff =
    new AliMUONTriggerChamberEfficiency( (AliMUONTriggerEfficiencyCells*)obj );

  //AliMUONTriggerEfficiencyCells *eff = (AliMUONTriggerEfficiencyCells*)obj;

  gStyle->SetPalette(1);

  eff->DisplayEfficiency();

}
