/** Modified by Dario Berzano <dario.berzano@gmail.com>
 */
void runEMT2() {

  // Base ROOT libraries
  gSystem->Load("libTree");
  gSystem->Load("libGeom");
  gSystem->Load("libVMC");
  gSystem->Load("libPhysics");
  gSystem->Load("libMinuit");

  gSystem->AddIncludePath("-I\"$ALICE_ROOT/include\"");
  gSystem->AddIncludePath("-I\"$ALICE_ROOT/MUON\"");

  // AliRoot libraries
  gSystem->Load("libSTEERBase");
  gSystem->Load("libESD");
  gSystem->Load("libAOD");
  gSystem->Load("libANALYSIS");
  gSystem->Load("libANALYSISalice");
  gSystem->Load("libMUONtrigger");

  TString ocdbPath = Form("local://%s/OCDB", gSystem->pwd());

  gROOT->LoadMacro("AliAnalysisTaskExtractMuonTracks.cxx+");
  AliAnalysisTaskExtractMuonTracks *task =
    new AliAnalysisTaskExtractMuonTracks("myEMT", kTRUE, 12345, ocdbPath);

  mgr = new AliAnalysisManager("ExtractMT");
  mgr->AddTask(task);

  AliESDInputHandler* esdH = new AliESDInputHandler;
  esdH->SetReadFriends(kFALSE);
  mgr->SetInputEventHandler(esdH);

  cInput = mgr->GetCommonInputContainer();
  mgr->ConnectInput(task, 0, cInput);

  cOutput = mgr->CreateContainer("tree", TTree::Class(),
    AliAnalysisManager::kOutputContainer, "mtracks.root");
  mgr->ConnectOutput(task, 1, cOutput);

  cOutputPt = mgr->CreateContainer("lf", TList::Class(),
    AliAnalysisManager::kOutputContainer, "mtracks.root");
  mgr->ConnectOutput(task, 2, cOutputPt);

  mgr->SetDebugLevel(0); // >0 to disable progressbar, which only appears with 0
  mgr->InitAnalysis();
  mgr->PrintStatus();

  TChain *chain = new TChain("esdTree");
  // good chain
  chain->Add( "alien:///alice/sim/PDC_09/LHC09a6/92000/993/AliESDs.root" );
  //chain->Add(Form("%s/AliESDs.root",gSystem->pwd()));

  TGrid::Connect("alien:");
  mgr->StartAnalysis("local", chain);

  cout << endl << endl;  // cleaner output

}
