/** By Dario Berzano <dario.berzano@gmail.com>
 */

TString taskPrefix = "/dalice05/berzano";
Bool_t restoreMcLabel = kFALSE;

void runMultiple() {
  TString cdbModes[] = { "50pct-maxcorr", "75pct-maxcorr", "r-maxcorr" };
  UInt_t nModes = sizeof(cdbModes)/sizeof(TString);

  loadLibs();
  gROOT->LoadMacro("AliAnalysisTaskAppMtrEff.cxx++");
  if (restoreMcLabel) {
    gROOT->LoadMacro(
      "$ALICE_ROOT/PWG3/muondep/AliAnalysisTaskESDMCLabelAddition.cxx++"
    );
  }

  for (UInt_t i=0; i<nModes; i++) {

    for (UInt_t j=0; j<2; j++) {
      TString cmd = Form("screen -dmS ali%u%u aliroot -b -q runAppMtrEff.C'(\"%s\", \"%s\")'",
        i, j,
        cdbModes[i].Data(),
        (j==0) ? "" : "fulleff");
      gSystem->Exec(cmd.Data());
    }

  }

}

void runAppMtrEff(
  TString cdbMode = "r-maxcorr",
  TString effMode = "", /* fulleff */
  TString simMode = "real-2mu"
) {

  if (effMode.IsNull()) effMode = cdbMode;

  TString cdb = Form("local://%s/cdb/%s", taskPrefix.Data(), cdbMode.Data());

  //////////////////////////////////////////////////////////////////////////////
  // Local run for test (on my Mac)
  //////////////////////////////////////////////////////////////////////////////
  /*
  TChain *chain = new TChain("esdTree");
  chain->Add( Form("%s/../misc/bogdan/macros_20100714-164117/AliESDs.root",
    gSystem->pwd()) );
  //chain->Add( "alien:///alice/sim/PDC_09/LHC09a6/92000/993/AliESDs.root" );
  gSystem->Unlink("mtracks-test.root");
  runTask(chain, "mtracks-test.root", kTRUE, cdb);
  */

  //////////////////////////////////////////////////////////////////////////////
  // Run on the LPC farm, move results to proper folder, with my data
  //////////////////////////////////////////////////////////////////////////////
  /*
  gROOT->LoadMacro("CreateChainFromFind.C");
  TChain *chain = CreateChainFromFind(
    Form("%s/jobs/sim-%s-%s", taskPrefix.Data(), simMode.Data(), effMode.Data()),
    "AliESDs.root",
    "esdTree",
    1e9,
    kTRUE
  );
  */
  gROOT->LoadMacro("CreateChainFromText.C");
  TChain *chain = CreateChainFromText(
    Form("%s/jobs/sim-%s-%s/partial_matching.txt",
      taskPrefix.Data(), simMode.Data(), effMode.Data()),
    "esdTree", kTRUE
  );

  TString output;
  if (cdbMode == effMode) {
    output = Form("mtracks-%s.root", cdbMode.Data());
  }
  else {
    output = Form("mtracks-%s-%s.root", cdbMode.Data(), effMode.Data());
  }

  TString dest = Form("%s/outana/app-mtr-eff/sim-%s",
    taskPrefix.Data(),
    simMode.Data());

  // Remove previous data (watch out!)
  gSystem->Unlink( Form("%s/%s", dest.Data(), output.Data()) );

  if (effMode == "fulleff") {
    // Here, we apply the efficiencies
    runTask(chain, output, kTRUE, cdb);
  }
  else {
    // Here, efficiencies have already been applied in the sim+rec
    runTask(chain, output, kFALSE);
  }

  gSystem->mkdir(dest, kTRUE);
  gSystem->Exec(Form("mv %s \"%s\"", output.Data(), dest.Data()));
  Printf("==== Content of %s ====", dest.Data());
  gSystem->Exec(Form("ls -l \"%s\"", dest.Data()));

  //////////////////////////////////////////////////////////////////////////////
  // Run on the LPC farm, move results to proper folder, with Xavier's data
  //////////////////////////////////////////////////////////////////////////////
  /*TString effModeXavier;
  if (effMode == "reff") effModeXavier = "R";
  else if (effMode == "fulleff") effModeXavier = "100";

  gROOT->LoadMacro("CreateChainFromText.C");
  TChain *chain = CreateChainFromText(
    Form("/users/divers/alice/berzano/list_xavier_%s.txt", effMode.Data()),
    "esdTree",
    kTRUE
  );
  TString output = Form("mtracks-%s.root", effMode.Data());
  TString dest = "/dalice05/berzano/outana/app-mtr-eff/sim-xavier";

  if (effMode == "reff") {
    // Here, efficiencies have already been applied in the sim+rec
    runTask(chain, output, kFALSE);
  }
  else if (effMode == "fulleff") {
    // Here, we apply the efficiencies
    runTask(chain, output, kTRUE, cdb);
  }

  gSystem->mkdir(dest, kTRUE);
  gSystem->Exec(Form("mv %s \"%s\"", output.Data(), dest.Data()));
  Printf("==== Content of %s ====", dest.Data());
  gSystem->Exec(Form("ls -l \"%s\"", dest.Data()));
  */

}

void loadLibs() {

  // Base ROOT libraries
  gSystem->Load("libTree");
  gSystem->Load("libGeom");
  gSystem->Load("libVMC");
  gSystem->Load("libPhysics");
  gSystem->Load("libMinuit");

  // Include paths for AliRoot
  gSystem->AddIncludePath("-I\"$ALICE_ROOT/include\"");
  gSystem->AddIncludePath("-I\"$ALICE_ROOT/MUON\"");
  gSystem->AddIncludePath("-I\"$ALICE_ROOT/MUON/mapping\"");

  // AliRoot libraries
  gSystem->Load("libSTEERBase");
  gSystem->Load("libESD");
  gSystem->Load("libAOD");
  gSystem->Load("libANALYSIS");
  gSystem->Load("libANALYSISalice");
  gSystem->Load("libMUONtrigger");
  
}

void runTask(TChain *input, TString output, Bool_t applyEff, TString cdb = "") {

  loadLibs();

  // Print a banner
  cout << endl;
  cout << "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" << endl;
  if (applyEff) {
    cout << "!! I am APPLYING efficiencies (FAST method)" << endl;
    cout << "!! OCDB: " << cdb << endl;
  }
  else {
    cout << "!! I am NOT applying efficiencies" << endl;
  }
  cout << "!! I am " << (restoreMcLabel ? "RESTORING" : "NOT restoring") <<
    " missing MC labels!" << endl;
  cout << "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" << endl;
  cout << endl;

  // Remove extra error messages, leave the progress bar alone STP!
  AliLog::SetGlobalLogLevel(AliLog::kFatal);

  gROOT->LoadMacro("AliAnalysisTaskAppMtrEff.cxx+");
  //gSystem->Exit(66);
  AliAnalysisTaskAppMtrEff *task =
    new AliAnalysisTaskAppMtrEff("myAppMtrEff", applyEff, 0, cdb);

  mgr = new AliAnalysisManager("ExtractMT");

  AliAnalysisTask *taskAddLab = 0x0;
  if (restoreMcLabel) {
    gROOT->LoadMacro(
      "$ALICE_ROOT/PWG3/muondep/AliAnalysisTaskESDMCLabelAddition.cxx+"
    );
    taskAddLab = new AliAnalysisTaskESDMCLabelAddition("myAppAddLabel");
    mgr->AddTask(taskAddLab);
  }

  mgr->AddTask(task);

  AliESDInputHandler* esdH = new AliESDInputHandler();
  esdH->SetReadFriends(kFALSE);
  mgr->SetInputEventHandler(esdH);

  AliMCEventHandler *mcH = new AliMCEventHandler();
  mgr->SetMCtruthEventHandler(mcH);

  //////////////////////////////////////////////////////////////////////////////
  ///////////////////////////////////// IO /////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////

  cInput = mgr->GetCommonInputContainer();

  if (restoreMcLabel) {
    mgr->ConnectInput(taskAddLab, 0, cInput);
  }
  mgr->ConnectInput(task, 0, cInput);

  cOutputRec = mgr->CreateContainer("recoMu", TTree::Class(),
    AliAnalysisManager::kOutputContainer, output);
  mgr->ConnectOutput(task, 0, cOutputRec);

  cOutputMc = mgr->CreateContainer("mcMu", TTree::Class(),
    AliAnalysisManager::kOutputContainer, output);
  mgr->ConnectOutput(task, 1, cOutputMc);

  cOutputPt = mgr->CreateContainer("histos", TList::Class(),
    AliAnalysisManager::kOutputContainer, output);
  mgr->ConnectOutput(task, 2, cOutputPt);

  //////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////// End of IO /////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////

  mgr->SetDebugLevel(0); // >0 to disable progressbar, which only appears with 0
  mgr->SetUseProgressBar(kTRUE);
  mgr->InitAnalysis();
  mgr->PrintStatus();

  mgr->StartAnalysis("local", input);

  cout << endl << endl;  // cleaner output

}
