void minimalProofTest() {

  // TString swName = "AliRoot";
  // //TString swVer = "vAN-20141201";
  // //TString swVer = "vAN-20150107";
  // TString swVer = "v5-06-02";

  TString swName = "AliPhysics";
  //TString swVer = "vAN-20141201";
  //TString swVer = "vAN-20150107";
  TString swVer = "vAN-20150129";

  TString rootVer = "v5-34-08-6";
  TString connStr = "dberzano@alice-caf.cern.ch";

  gSystem->Exec( "rm -f VO*.par 2> /dev/null" );
  gSystem->Exec( Form("./gen_single_par.sh 'VO_ALICE@%s::%s'", swName.Data(), swVer.Data()) );

  TProof::Reset(connStr.Data());
  TProof::Mgr(connStr.Data())->SetROOTVersion(Form("VO_ALICE@ROOT::%s", rootVer.Data()));
  TProof::Open(connStr.Data(), "masteronly");
  if (!gProof) return;

  gProof->ClearPackages();
  gProof->UploadPackage( Form("VO_ALICE@%s::%s", swName.Data(), swVer.Data()) );
  gProof->EnablePackage( Form("VO_ALICE@%s::%s", swName.Data(), swVer.Data()) );

  // Run some tests
  Printf("* What is ALICE_ROOT on the remote node?");
  gProof->Exec( ".!echo $ALICE_ROOT" );
  Printf("* What is ALICE_PHYSICS on the remote node?");
  gProof->Exec( ".!echo $ALICE_PHYSICS" );
  Printf("* What is the library path?");
  gProof->Exec( "cout << gSystem->GetDynamicPath() << endl;" );
  Printf("* What is the include path?");
  gProof->Exec( "cout << gSystem->GetIncludePath() << endl;" );
  Printf("* What is the macro path?");
  gProof->Exec( "cout << gROOT->GetMacroPath() << endl;" );
}
