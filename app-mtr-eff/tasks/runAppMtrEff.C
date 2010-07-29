/** By Dario Berzano <dario.berzano@gmail.com>
 */
void runAppMtrEff(TString mode) {

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

  TString ocdbTrigChEff = Form("local://%s/../cdb/%s", gSystem->pwd(),
    mode.Data());

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
  TString output = Form("mtracks-%s.root", mode.Data());
  gSystem->Unlink(output);

  cOutput = mgr->CreateContainer("tree", TTree::Class(),
    AliAnalysisManager::kOutputContainer, output);
  mgr->ConnectOutput(task, 1, cOutput);

  cOutputPt = mgr->CreateContainer("histos", TList::Class(),
    AliAnalysisManager::kOutputContainer, output);
  mgr->ConnectOutput(task, 2, cOutputPt);

  mgr->SetDebugLevel(0); // >0 to disable progressbar, which only appears with 0
  mgr->InitAnalysis();
  mgr->PrintStatus();

  TChain *chain = CreateChainFromFind(
    Form("/dalice05/berzano/jobs/sim-mu-highp-%s", mode.Data()),
    "AliESDs.root",
    "esdTree"
  );

  /*
  TChain *chain = new TChain("esdTree");
  chain->Add(Form("%s/../misc/bogdan/macros_20100714-164117/AliESDs.root",
    gSystem->pwd()));
  //TGrid::Connect("alien:");
  //chain->Add( "alien:///alice/sim/PDC_09/LHC09a6/92000/993/AliESDs.root" );
  //chain->Add(Form("%s/AliESDs.root",gSystem->pwd()));
  */

  mgr->StartAnalysis("local", chain);

  cout << endl << endl;  // cleaner output

}

TChain *CreateChainFromFind(TString &path, TString &file, TString &tree,
  Int_t limit = 1e9, Bool_t verbose = kFALSE) {

  TChain *ch = new TChain(tree);
  TString out = gSystem->GetFromPipe( Form("find \"%s/\" -name \"%s\"",
    path.Data(), file.Data()) );
  TObjArray *aptr = out.Tokenize("\r\n");
  TObjArray &a = *aptr;

  if (verbose) Printf("Files to add to the chain: %d", a.GetEntries());

  for (Int_t i=0; i<a.GetEntries() && i<limit; i++) {
    TObjString *os = dynamic_cast<TObjString *>(a[i]);
    TString &s = os->String();
    if (verbose) Printf(">> Adding to chain: %s", s.Data());
    ch->Add(s);
  }

  delete aptr;

  return ch;
}
