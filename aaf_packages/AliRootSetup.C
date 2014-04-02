/*
 * SETUP.C -- by Dario Berzano <dario.berzano@cern.ch>
 *
 * Configures environment for a certain AliRoot version.
 *
 * List of variables to support for compatibility:
 *
 * ALICE_PROOF_AAF_ALIEN_PACKAGES
 * [X] ALIROOT_EXTRA_INCLUDES
 * [X] ALIROOT_MODE
 * [X] ALIROOT_EXTRA_LIBS
 * [ ] ALIROOT_AAF_BAD_WORKER
 * [ ] ALIROOT_AAF_DEBUG
 * [X] ALIROOT_ENABLE_ALIEN
 * [ ] ALIROOT_ALIEN_RETRY
 *
 */

#if !defined(__CINT__) || defined (__MAKECINT__)
#include <TError.h>
#include <TSystem.h>
#include <Riostream.h>
#include <TROOT.h>
#include <TList.h>
#include <TProof.h>
#include <TPRegexp.h>
#include <TObjString.h>
#include <TGrid.h>
#endif

TString gMessTag;

//______________________________________________________________________________
Bool_t SETUP_LoadLibraries(const TString &libs) {

  // Loads a list of colon-separated libraries. Returns kTRUE on success, kFALSE
  // if at least one library couldn't load properly. Does not check for double
  // loads (but ROOT does).

  TObjArray *toks = libs.Tokenize(":");
  TIter it(toks);
  TObjString *os;

  while ((os = dynamic_cast<TObjString *>( it.Next() )) != NULL) {
    TString l = os->String();
    if (l.IsNull()) continue;
    if (!l.BeginsWith("lib")) l.Prepend("lib");
    if (l.EndsWith(".so")) l.Remove(l.Length()-3, l.Length());

    ::Info(gMessTag.Data(), ">> Loading %s...", l.Data());

    if (gSystem->Load(l.Data()) < 0) {
       ::Error(gMessTag.Data(), "Error loading %s, aborting", l.Data());
       return kFALSE;  // failure
    }
  }

  return kTRUE;  // success

  return 0;
}

//______________________________________________________________________________
Bool_t SETUP_SetAliRootMode(TString &mode, const TString &extraLibs) {

  // Sets a certain AliRoot mode, defining a set of libraries to load. Extra
  // libraries to load can be specified as well. Returns kTRUE on success, or
  // kFALSE in case library loading failed.

  mode.ToLower();
  TString libs = extraLibs;
  Long_t rv = -9999;

  // Load needed ROOT libraries
  if (!SETUP_LoadLibraries("VMC:Tree:Physics:Matrix:Minuit:XMLParser:Gui")) {
    ::Error(gMessTag.Data(), "Loading of extra ROOT libraries failed");
    return kFALSE;
  }

  if (mode == "aliroot") {
    ::Info(gMessTag.Data(), "Loading libraries for aliroot mode...");
    rv = gROOT->Macro(
      gSystem->ExpandPathName("$ALICE_ROOT/macros/loadlibs.C") );
  }
  else if (mode == "sim") {
    ::Info(gMessTag.Data(), "Loading libraries for simulation mode...");
    rv = gROOT->Macro(
      gSystem->ExpandPathName("$ALICE_ROOT/macros/loadlibssim.C") );
  }
  else if (mode == "rec") {
    ::Info(gMessTag.Data(), "Loading libraries for reconstruction mode...");
    rv = gROOT->Macro(
      gSystem->ExpandPathName("$ALICE_ROOT/macros/loadlibsrec.C") );
  }
  else {
    // No mode specified, or invalid mode: load standard libraries, and also
    // fix loading order
    TPMERegexp reLibs("(ANALYSISalice|OADB|ANALYSIS|STEERBase|ESD|AOD)(:|$)");
    while (reLibs.Substitute(libs, "")) {}
    libs.Prepend("STEERBase:ESD:AOD:ANALYSIS:OADB:ANALYSISalice:");
  }

  // Check status code
  if (rv == 0) {
    ::Info(gMessTag.Data(), "Successfully loaded AliRoot base libraries");
  }
  else if (rv != -9999) {
    ::Error(gMessTag.Data(), "Loading of base AliRoot libraries failed");
    return kFALSE;
  }

  // Load extra AliRoot libraries
  ::Info(gMessTag.Data(), "Loading extra AliRoot libraries...");
  if (!SETUP_LoadLibraries(libs)) {
    ::Error(gMessTag.Data(), "Loading of extra AliRoot libraries failed");
    return kFALSE;
  }
  else {
    ::Info(gMessTag.Data(), "Successfully loaded extra AliRoot libraries");
  }

  return kTRUE;
}

Int_t SETUP(TList *inputList = NULL) {

  TString aliRootDir;

  if (gProof && !gProof->IsMaster()) {

    //
    // On client
    //

    gMessTag = "Client";
    aliRootDir = gSystem->Getenv("ALICE_ROOT");  // NULL --> ""

    if (aliRootDir.IsNull()) {
      ::Error(gMessTag.Data(),
        "ALICE_ROOT environment variable not defined on client");
      return -1;
    }

    ::Info(gMessTag.Data(), "Enabling AliRoot located at %s",
      aliRootDir.Data());

  }
  else {

    //
    // On master/workers
    //

    gMessTag = gSystem->HostName();

    // Extract AliRoot version from this package's name
    TString aliRootVer = gSystem->BaseName(gSystem->pwd());
    TPMERegexp re("^VO_ALICE@AliRoot::(.*)$");
    if (re.Match(aliRootVer) != 2) {
      ::Error(gMessTag.Data(),
        "Error parsing requested AliRoot version from PARfile name (%s)",
        aliRootVer.Data());
      return -1;
    }

    aliRootVer = re[1].Data();
    ::Info(gMessTag.Data(), "Enabling AliRoot %s...", aliRootVer.Data());

    // Get ALICE_ROOT from Modules
    TString buf;
    buf.Form( ". /cvmfs/alice.cern.ch/etc/login.sh && eval `alienv printenv VO_ALICE@AliRoot::%s` && echo \"$ALICE_ROOT\"", aliRootVer.Data() );
    aliRootDir = gSystem->GetFromPipe( buf.Data() );

    // Set environment for AliRoot
    gSystem->Setenv("ALICE_ROOT", aliRootDir.Data());

    // LD_LIBRARY_PATH: current working directory always has precedence
    gSystem->SetDynamicPath(
      Form(".:%s/lib/tgt_%s:%s", aliRootDir.Data(), gSystem->GetBuildArch(),
        gSystem->GetDynamicPath()) );

  }

  //
  // Common operations on Client and PROOF Master/Workers
  //

  // Add standard AliRoot include path
  gSystem->AddIncludePath(Form("-I\"%s/include\"", aliRootDir.Data()));

  // Add standard AliRoot macro path
  gROOT->SetMacroPath(
    Form("%s:%s/macros", gROOT->GetMacroPath(), aliRootDir.Data()) );

  //
  // Process input parameters
  //

  TString extraIncs, extraLibs, mode;
  Bool_t enableAliEn = kFALSE;

  if (inputList) {
    TIter it(inputList);
    TNamed *pair;
    while ((pair = dynamic_cast<TNamed *>(it.Next()))) {
      if ( strcmp(pair->GetName(), "ALIROOT_EXTRA_INCLUDES") == 0 )
        extraIncs = pair->GetTitle();
      else if ( strcmp(pair->GetName(), "ALIROOT_EXTRA_LIBS") == 0 )
        extraLibs = pair->GetTitle();
      else if ( strcmp(pair->GetName(), "ALIROOT_ENABLE_ALIEN") == 0 )
        enableAliEn = ( *(pair->GetTitle()) != '\0' );
    }
  }

  //
  // Load extra libraries and set AliRoot mode
  //

  if (!SETUP_SetAliRootMode(mode, extraLibs)) {
    ::Error(gMessTag.Data(),
      "Error loading libraries while setting AliRoot mode.");
    ::Error(gMessTag.Data(),
      "Did you enable the right version of ROOT?");
    return -1;
  }

  //
  // Set extra includes
  //

  {
    TObjArray *toks = extraIncs.Tokenize(":");
    TIter it(toks);
    TObjString *os;

    while ((os = dynamic_cast<TObjString *>( it.Next() )) != NULL) {
      TString &inc = os->String();
      if (inc.IsNull()) continue;
      ::Info(gMessTag.Data(), ">> Adding include path %s", inc.Data());
      gSystem->AddIncludePath(
        Form("-I\"%s/%s\"", aliRootDir.Data(), inc.Data()) );
    }
  }

  //
  // Enable AliEn
  //

  if (enableAliEn) {
    ::Info(gMessTag.Data(), "Connecting to AliEn...");
    TGrid::Connect("alien:");
    if (!gGrid) {
      ::Error(gMessTag.Data(), "Cannot connect to AliEn");
      return -1;
    }
    else {
      ::Info(gMessTag.Data(), "Successfully connected to AliEn");
    }
  }

  return 0;
}
