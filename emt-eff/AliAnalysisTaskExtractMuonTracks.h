#ifndef ALIANALYSISTASKEXTRACTMUONTRACKS_H
#define ALIANALYSISTASKEXTRACTMUONTRACKS_H

// ROOT includes
#include <TH1F.h>
#include <TChain.h>
#include <TTree.h>
#include <TFile.h>
#include <TRandom3.h>
#include <TString.h>
#include <TClonesArray.h>
#include <TCanvas.h>
#include <TROOT.h>
#include <TStyle.h>

// AliRoot includes
#include "AliAnalysisManager.h"
#include "AliAnalysisTaskSE.h"
#include "AliCDBManager.h"
#include "AliCDBEntry.h"
#include "AliESDEvent.h"
#include "AliESDInputHandler.h"
#include "AliESDMuonTrack.h"
#include "AliMUONTriggerChamberEfficiency.h"
#include "AliMUONTriggerEfficiencyCells.h"
#include "AliMUONTrackParam.h"
#include "AliMUONESDInterface.h"
#include "AliMUONTrackExtrap.h"
#include "AliMUONConstants.h"
#include "AliMUONCDB.h"
#include "AliMUONTrack.h"
#include "AliLog.h"

/** Definiton of the Event class. This is a simple container class that contains
 *  a TClonesArray of tracks for a given event.
 */
class Event : public TObject {

public: 

  Event(const char *esdFileName = "", Int_t evNum = -1);
  virtual ~Event();

  TClonesArray *GetTracks() { return fTracks; }
  const Char_t *GetESDFileName() { return fESDFileName.Data(); }
  Int_t GetEventNumber() { return fEventInList; }

private:

  TClonesArray *fTracks;
  TString       fESDFileName;
  Int_t         fEventInList;

  ClassDef(Event, 1);

};

/** Definiton of the analysis task that extracts muon tracks from an ESD. The
 *  analysis task can also be configured to mark some tracks as triggered or not
 *  triggered, if we want to apply the efficiency correction at ESD level. For
 *  this procedure, the OCDB is used, and the map of efficiencies should be
 *  put in the custom specific storage for the OCDB.
 */
class AliAnalysisTaskExtractMuonTracks : public AliAnalysisTaskSE {

  public:

    typedef enum { kLocTrig = 1, kLocTrack = 2, kLocBoth = 3 } MuonTrackLoc_t;

    // See http://aliweb.cern.ch/Offline/Activities/Analysis/AnalysisFramework/
    // index.html >> we should not DefineInput/Output in the default constructor
    AliAnalysisTaskExtractMuonTracks() {};

    AliAnalysisTaskExtractMuonTracks(const char *name,
      Bool_t applyEfficiencies = kFALSE, Int_t runNum = -1,
      const char *ocdbTrigChEff = NULL, const char *ocdbMagField = NULL);
    virtual ~AliAnalysisTaskExtractMuonTracks() {}

    virtual void UserCreateOutputObjects();
    virtual void UserExec(Option_t *opt);
    virtual void Terminate(Option_t *opt);

  protected:

    virtual Bool_t KeepTrackByEff(AliESDMuonTrack *muTrack);

  private:

    TTree       *fTreeOut;              //! Output tree
    Event       *fEvent;                //! Output event

    TList       *fHistoList;            //! List that containts output histos
    TH1F        *fHistoPt;              //! Output Pt distro
    TH1F        *fHistoTrLoc;           //! Output tracks locations count
    TH1F        *fHistoEffFlag;         //! Efficiency flag of muon tracks
    TH1F        *fHistoTheta;           //! Theta distro
    TH1F        *fHistoPhi;             //! Phi distro
    TH1F        *fHistoP;               //! Total momentum distro
    TH1F        *fHistoDca;             //! DCA distro
    TH1F        *fHistoChHit;           //! Chambers hit (per plane)
    TH1F        *fHistoBendHit;         //! Hits on bending plane
    TH1F        *fHistoNBendHit;        //! Hits on nonbending plane

    Bool_t       fApplyEff;             //! If kTRUE, apply effs a posteriori

    AliMUONTriggerChamberEfficiency *fTrigChEff;  //! Handler of chamber effs

    // Copy constructor and equals operator are disabled for this class
    AliAnalysisTaskExtractMuonTracks(const AliAnalysisTaskExtractMuonTracks &);
    AliAnalysisTaskExtractMuonTracks& operator=(
      const AliAnalysisTaskExtractMuonTracks&);
 
    ClassDef(AliAnalysisTaskExtractMuonTracks, 1);
};

#endif // ALIANALYSISTASKEXTRACTMUONTRACKS_H
