/** Modified by Dario Berzano <dario.berzano@gmail.com>
 */
{

  // Base ROOT libraries
  gSystem->Load("libTree");
  gSystem->Load("libGeom");
  gSystem->Load("libVMC");
  gSystem->Load("libPhysics");
  gSystem->Load("libMinuit");

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

  //TString ocdbTrigChEff = Form("local://%s/ocdb_fulleff", gSystem->pwd());
  TString ocdbTrigChEff = Form("local://%s/ocdb_reff", gSystem->pwd());

  gROOT->LoadMacro("AliAnalysisTaskAppMtrEff.cxx+");
  AliAnalysisTaskAppMtrEff *task =
    new AliAnalysisTaskAppMtrEff("myAppMtrEff", kTRUE, 0, ocdbTrigChEff);

  mgr = new AliAnalysisManager("ExtractMT");
  mgr->AddTask(task);

  AliESDInputHandler* esdH = new AliESDInputHandler;
  esdH->SetReadFriends(kFALSE);
  mgr->SetInputEventHandler(esdH);

  cInput = mgr->GetCommonInputContainer();
  mgr->ConnectInput(task, 0, cInput);

  // Remove previous output result (WATCH OUT!)
  gSystem->Unlink("mtracks.root");

  cOutput = mgr->CreateContainer("tree", TTree::Class(),
    AliAnalysisManager::kOutputContainer, "mtracks.root");
  mgr->ConnectOutput(task, 1, cOutput);

  cOutputPt = mgr->CreateContainer("histos", TList::Class(),
    AliAnalysisManager::kOutputContainer, "mtracks.root");
  mgr->ConnectOutput(task, 2, cOutputPt);

  mgr->SetDebugLevel(0); // >0 to disable progressbar, which only appears with 0
  mgr->InitAnalysis();
  mgr->PrintStatus();

  TChain *chain = new TChain("esdTree");
  // good chain
  chain->Add(Form("%s/Bogdan/macros_20100714-164117/AliESDs.root",
    gSystem->pwd()));
  //chain->Add( "alien:///alice/sim/PDC_09/LHC09a6/92000/993/AliESDs.root" );
  //chain->Add(Form("%s/AliESDs.root",gSystem->pwd()));

  //TGrid::Connect("alien:");
  mgr->StartAnalysis("local", chain);

  cout << endl << endl;  // cleaner output

}
