simrec() {
  // extract the run and event variables given with
  // --run <x> --event <y> --type <t>
  // where "type" can be "ppMBias" or "pptrg2mu"

  Int_t nRun    = 0;
  Int_t nEvents = 0;

  TString buf;
  TString type = "";
  TString cdb = "";

  for (Int_t i=0; i< gApplication->Argc(); i++) {

    if ((strcmp(gApplication->Argv(i), "--run")) == 0) {
      buf = gApplication->Argv(i+1);
      nRun = buf.Atoi();
    }
    else if ((strcmp(gApplication->Argv(i), "--events")) == 0) {
      buf = gApplication->Argv(i+1);
      nEvents = buf.Atoi();
    }
    else if ((strcmp(gApplication->Argv(i), "--type")) == 0) {
      type = gApplication->Argv(i);
    }
    else if ((strcmp(gApplication->Argv(i), "--cdb")) == 0) {
      cdb = gApplication->Argv(i+1);
    }

  }

  Int_t seed = nRun * 100000 + nEvents;

  Printf("*** run=%d events=%d seed=%d ***", nRun, nEvents, seed);

  gSystem->Setenv("CONFIG_SEED", Form("%d", seed));
  gSystem->Setenv("CONFIG_RUN_TYPE", type.Data());
  gSystem->Setenv("DC_RUN", Form("%d", nRun));
  if (!cdb.IsNull()) gSystem->Setenv("ALI_MTR_CDB", cdb);

  TStopwatch sw;

  // Simulation
  gSystem->Exec( Form("aliroot -b -q 'sim.C(%d)' > sim.log 2>&1", nEvents) );

  // Some more stuff...
  gSystem->mkdir("generated", kTRUE);
  gSystem->Exec("mv *.root generated/");
  gSystem->Exec("mv generated/raw.root .");
  gSystem->Exec("mv generated/geometry.root .");

  // Reconstruction
  gSystem->Exec("aliroot -b -q rec.C > rec.log 2>&1");

  // Verify if everything went right (validation). WATCH OUT! AccessPathName
  // returns kFALSE if the file CAN be accessed!
  if (!gSystem->AccessPathName("AliESDs.root")) {
    // File CAN be accessed: move everything in right place
    gSystem->Exec("mv generated/* .");
    gSystem->Exec("rm -rf generated/");
  }
  else {
    // Validation error!
    Printf("**** VALIDATION ERROR! ****");
  }

  Printf("*** Global Timer ***");
  sw.Print();

}
