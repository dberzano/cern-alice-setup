/** By Dario Berzano <dario.berzano@gmail.com>
 */
void runAppMtrEff() {

  TString effMode = "50eff";  // "reff", "fulleff"
  TString cdb = "local:///dalice05/berzano/cdb/50eff";

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
  TString simMode = "mumin-onemu-15gev";
  gROOT->LoadMacro("CreateChainFromFind.C");
  TChain *chain = CreateChainFromFind(
    Form("/dalice05/berzano/jobs/sim-%s-%s", simMode.Data(), effMode.Data()),
    "AliESDs.root",
    "esdTree"
  );
  TString output = Form("mtracks-%s.root", effMode.Data());
  TString dest = Form("/dalice05/berzano/outana/app-mtr-eff/sim-%s",
    simMode.Data());

  // Remove previous data (watch out!)
  gSystem->Unlink( Form("%s/%s", dest.Data(), output.Data()) );

  if (effMode == "50eff") {
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

void runTask(TChain *input, TString output, Bool_t applyEff, TString cdb = "") {

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

  gROOT->LoadMacro("AliAnalysisTaskAppMtrEff.cxx+");
  AliAnalysisTaskAppMtrEff *task =
    new AliAnalysisTaskAppMtrEff("myAppMtrEff", applyEff, 0, cdb);

  mgr = new AliAnalysisManager("ExtractMT");
  mgr->AddTask(task);

  AliESDInputHandler* esdH = new AliESDInputHandler();
  esdH->SetReadFriends(kFALSE);
  mgr->SetInputEventHandler(esdH);

  AliMCEventHandler *mcH = new AliMCEventHandler();
  mgr->SetMCtruthEventHandler(mcH);

  cInput = mgr->GetCommonInputContainer();
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

  mgr->SetDebugLevel(0); // >0 to disable progressbar, which only appears with 0
  mgr->InitAnalysis();
  mgr->PrintStatus();

  mgr->StartAnalysis("local", input);

  cout << endl << endl;  // cleaner output

}
