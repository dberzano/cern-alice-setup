/** By Dario Berzano <dario.berzano@gmail.com>
 */
void runAppMtrEff() {

  TString mode = "fulleff";
  TString cdb = Form("local://%s/../cdb/%s", gSystem->pwd(), mode.Data());

  // Local run for test (on my Mac)
  TChain *chain = new TChain("esdTree");
  chain->Add( Form("%s/../misc/bogdan/macros_20100714-164117/AliESDs.root",
    gSystem->pwd()) );
  //chain->Add( "alien:///alice/sim/PDC_09/LHC09a6/92000/993/AliESDs.root" );
  gSystem->Unlink("mtracks-test.root");
  runTask(chain, "mtracks-test.root", cdb);

  // Run on the LPC farm
  /*
  gROOT->LoadMacro("CreateChainFromFind.C");
  TChain *chain = CreateChainFromFind(
    Form("/dalice05/berzano/jobs/sim-mu-highp-%s", mode.Data()),
    "AliESDs.root",
    "esdTree"
  );
  TString output = Form("mtracks-%s", mode.Data());
  runTask(chain, output, cdb);
  */

}

void runTask(TChain *input, TString output, TString cdb) {

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
    new AliAnalysisTaskAppMtrEff("myAppMtrEff", kTRUE, 0, cdb);

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

  mgr->SetDebugLevel(1); // >0 to disable progressbar, which only appears with 0
  mgr->InitAnalysis();
  mgr->PrintStatus();

  mgr->StartAnalysis("local", input);

  cout << endl << endl;  // cleaner output

}
