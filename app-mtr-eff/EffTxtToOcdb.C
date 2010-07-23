{
  gROOT->LoadMacro("$ALICE_ROOT/MUON/MUONTriggerChamberEfficiency.C");
  MUONTriggerChamberEfficiency(
    Form("%s/efficiencyCellsData-R.dat", gSystem->pwd()),
    Form("local://%s/ocdb_reff", gSystem->pwd())
  );
}
