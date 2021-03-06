{ $Id$ }
{                  -------------------------------------------
                    DebuggerBase.pp  -  Debugger base classes
                   -------------------------------------------

 @author(Marc Weustink <marc@@dommelstein.net>)
 @author(Martin Friebe)

 This unit contains the base class definitions of the debugger. These
 classes are only definitions. Implemented debuggers should be
 derived from these.

 ***************************************************************************
 *                                                                         *
 *   This source is free software; you can redistribute it and/or modify   *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This code is distributed in the hope that it will be useful, but      *
 *   WITHOUT ANY WARRANTY; without even the implied warranty of            *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
 *   General Public License for more details.                              *
 *                                                                         *
 *   A copy of the GNU General Public License is available on the World    *
 *   Wide Web at <http://www.gnu.org/copyleft/gpl.html>. You can also      *
 *   obtain it by writing to the Free Software Foundation,                 *
 *   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.        *
 *                                                                         *
 ***************************************************************************
}
unit DbgIntfDebuggerBase;

{$mode objfpc}{$H+}

interface

uses DbgIntfBaseTypes, DbgIntfMiscClasses, LazClasses, LazLoggerBase, FileUtil,
  maps, LCLProc, Classes, sysutils, math, contnrs, LazMethodList;

const
  DebuggerIntfVersion = 0;

type
  EDebuggerException = class(Exception);
  EDBGExceptions = class(EDebuggerException);

  TDBGCommand = (
    dcRun,
    dcPause,
    dcStop,
    dcStepOver,
    dcStepInto,
    dcStepOut,
    dcRunTo,
    dcJumpto,
    dcAttach,
    dcDetach,
    dcBreak,
    dcWatch,
    dcLocal,
    dcEvaluate,
    dcModify,
    dcEnvironment,
    dcSetStackFrame,
    dcDisassemble,
    dcStepOverInstr,
    dcStepIntoInstr,
    dcSendConsoleInput
    );
  TDBGCommands = set of TDBGCommand;

  { Debugger states
    --------------------------------------------------------------------------
    dsNone:
      The debug object is created, but no instance of an external debugger
      exists.
      Initial state, leave with Init, enter with Done

    dsIdle:
      The external debugger is started, but no filename (or no other params
      required to start) were given.

    dsStop:
      (Optional) The execution of the target is stopped
      The external debugger is loaded and ready to (re)start the execution
      of the target.
      Breakpoints, watches etc can be defined

    dsPause:
      The debugger has paused the target. Target variables can be examined

    dsInternalPause:
      Pause, not visible to user.
      For examble auto continue breakpoint: Allow collection of Snapshot data

    dsInit:
      (Optional, Internal) The debugger is about to run

    dsRun:
      The target is running.

    dsError:
      Something unforseen has happened. A shutdown of the debugger is in
      most cases needed.

    -dsDestroying
      The debugger is about to be destroyed.
      Should normally happen immediate on calling Release.
      But the debugger may be in nested calls, and has to exit them first.
    --------------------------------------------------------------------------
  }
  TDBGState = (
    dsNone,
    dsIdle,
    dsStop,
    dsPause,
    dsInternalPause,
    dsInit,
    dsRun,
    dsError,
    dsDestroying
    );

  TDBGLocationRec = record
    Address: TDBGPtr;
    FuncName: String;
    SrcFile: String;
    SrcFullName: String;
    SrcLine: Integer;
  end;

  TDBGExceptionType = (
    deInternal,
    deExternal,
    deRunError
  );

  TDebuggerDataState = (ddsUnknown,                    //
                        ddsRequested, ddsEvaluating,   //
                        ddsValid,                      // Got a valid value
                        ddsInvalid,                    // Does not have a value
                        ddsError                       // Error, but got some Value to display (e.g. error msg)
                       );

  (* TValidState: State for breakpoints *)
  TValidState = (vsUnknown, vsValid, vsInvalid);

  TDBGEvaluateFlag =
    (defNoTypeInfo,        // No Typeinfo object will be returned
     defSimpleTypeInfo,    // Returns: Kind (skSimple, skClass, ..); TypeName (but does make no attempt to avoid an alias)
     defFullTypeInfo,      // Get all typeinfo, resolve all anchestors
     defClassAutoCast      // Find real class of instance, and use, instead of declared class of variable
    );
  TDBGEvaluateFlags = set of TDBGEvaluateFlag;

  { TRunningProcessInfo
    Used to enumerate running processes.
  }

  TRunningProcessInfo = class
  public
    PID: Cardinal;
    ImageName: string;
    constructor Create(APID: Cardinal; const AImageName: string);
  end;

  TRunningProcessInfoList = TObjectList;

  (* TDebuggerDataMonitor / TDebuggerDataSupplier
     - TDebuggerDataMonitor
       used by the IDE to receive/request updates on all data objects
     - TDebuggerDataSupplier
       used by the debugger to provide updates on all data objects
  *)

  TDebuggerIntf = class;
  TDebuggerDataSupplier = class;

  { TDebuggerDataMonitor }

  TDebuggerDataMonitor = class
  private
    FSupplier: TDebuggerDataSupplier;
    procedure SetSupplier(const AValue: TDebuggerDataSupplier);
  protected
    procedure DoModified; virtual;                                              // user-modified / xml-storable data modified
    procedure DoNewSupplier; virtual;
    property  Supplier: TDebuggerDataSupplier read FSupplier write SetSupplier;
    procedure DoStateChange(const {%H-}AOldState, {%H-}ANewState: TDBGState); virtual;
  public
    destructor Destroy; override;
  end;

  { TDebuggerDataSupplier }

  TDebuggerDataSupplier = class
  private
    FNotifiedState, FOldState: TDBGState;
    FDebugger: TDebuggerIntf;
    FMonitor: TDebuggerDataMonitor;
    procedure SetMonitor(const AValue: TDebuggerDataMonitor);
  protected
    procedure DoNewMonitor; virtual;
    property  Debugger: TDebuggerIntf read FDebugger write FDebugger;
  protected
    property  Monitor: TDebuggerDataMonitor read FMonitor write SetMonitor;

    procedure DoStateEnterPause; virtual;
    procedure DoStateLeavePause; virtual;
    procedure DoStateLeavePauseClean; virtual;
    procedure DoStateChange(const AOldState: TDBGState); virtual;

    property  NotifiedState: TDBGState read FNotifiedState;                     // The last state seen by DoStateChange
    property  OldState: TDBGState read FOldState;                               // The state before last DoStateChange
  public
    constructor Create(const ADebugger: TDebuggerIntf);
    destructor  Destroy; override;
  end;

{$region Breakpoints **********************************************************}
(******************************************************************************)
(**                                                                          **)
(**   B R E A K P O I N T S                                                  **)
(**                                                                          **)
(** Note: This part of the interface may/will still change to the            **)
(**       monitor/supplier concept                                         **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

  TDBGBreakPointKind = (
    bpkSource,  // source breakpoint
    bpkAddress, // address breakpoint
    bpkData     // data/watchpoint
  );

  TDBGWatchPointScope = (
    wpsLocal,
    wpsGlobal
  );

  TDBGWatchPointKind = (
    wpkWrite,
    wpkRead,
    wpkReadWrite
  );

  { TBaseBreakPoint }

  TBaseBreakPoint = class(TRefCountedColectionItem)
  protected
    FAddress: TDBGPtr;
    FWatchData: String;
    FEnabled: Boolean;
    FExpression: String;
    FHitCount: Integer;      // Current counter
    FBreakHitCount: Integer; // The user configurable value
    FKind: TDBGBreakPointKind;
    FLine: Integer;
    FWatchScope: TDBGWatchPointScope;
    FWatchKind: TDBGWatchPointKind;
    FSource: String;
    FValid: TValidState;
    FInitialEnabled: Boolean;
  protected
    procedure AssignLocationTo(Dest: TPersistent); virtual;
    procedure AssignTo(Dest: TPersistent); override;
    procedure DoBreakHitCountChange; virtual;
    procedure DoExpressionChange; virtual;
    procedure DoEnableChange; virtual;
    procedure DoHit(const ACount: Integer; var {%H-}AContinue: Boolean); virtual;
    procedure SetHitCount(const AValue: Integer);
    procedure DoKindChange; virtual;
    procedure SetValid(const AValue: TValidState);
  protected
    // virtual properties
    function GetAddress: TDBGPtr; virtual;
    function GetBreakHitCount: Integer; virtual;
    function GetEnabled: Boolean; virtual;
    function GetExpression: String; virtual;
    function GetHitCount: Integer; virtual;
    function GetKind: TDBGBreakPointKind; virtual;
    function GetLine: Integer; virtual;
    function GetSource: String; virtual;
    function GetWatchData: String; virtual;
    function GetWatchScope: TDBGWatchPointScope; virtual;
    function GetWatchKind: TDBGWatchPointKind; virtual;
    function GetValid: TValidState; virtual;

    procedure SetAddress(const AValue: TDBGPtr); virtual;
    procedure SetBreakHitCount(const AValue: Integer); virtual;
    procedure SetEnabled(const AValue: Boolean); virtual;
    procedure SetExpression(const AValue: String); virtual;
    procedure SetInitialEnabled(const AValue: Boolean); virtual;
    procedure SetKind(const AValue: TDBGBreakPointKind); virtual;
  public
    constructor Create(ACollection: TCollection); override;
    // PublicProtectedFix ide/debugmanager.pas(867,32) Error: identifier idents no member "SetLocation"
    property BreakHitCount: Integer read GetBreakHitCount write SetBreakHitCount;
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property Expression: String read GetExpression write SetExpression;
    property HitCount: Integer read GetHitCount;
    property InitialEnabled: Boolean read FInitialEnabled write SetInitialEnabled;
    property Kind: TDBGBreakPointKind read GetKind write SetKind;
    property Valid: TValidState read GetValid;
  public
    procedure SetLocation(const ASource: String; const ALine: Integer); virtual;
    procedure SetWatch(const AData: String; const AScope: TDBGWatchPointScope;
                       const AKind: TDBGWatchPointKind); virtual;
    // bpkAddress
    property Address: TDBGPtr read GetAddress write SetAddress;
    // bpkSource
    //   TDBGBreakPoint: Line is the line-number as stored in the debug info
    //   TIDEBreakPoint: Line is the location in the Source (potentially modified Source)
    property Line: Integer read GetLine;
    property Source: String read GetSource;
    // bpkData
    property WatchData: String read GetWatchData;
    property WatchScope: TDBGWatchPointScope read GetWatchScope;
    property WatchKind: TDBGWatchPointKind read GetWatchKind;
  end;
  TBaseBreakPointClass = class of TBaseBreakPoint;

  { TDBGBreakPoint }

  TDBGBreakPoint = class(TBaseBreakPoint)
  private
    FSlave: TBaseBreakPoint;
    function GetDebugger: TDebuggerIntf;
    procedure SetSlave(const ASlave : TBaseBreakPoint);
  protected
    procedure SetEnabled(const AValue: Boolean); override;
    procedure DoChanged; override;
    procedure DoStateChange(const AOldState: TDBGState); virtual;
    property  Debugger: TDebuggerIntf read GetDebugger;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Hit(var ACanContinue: Boolean);
    property Slave: TBaseBreakPoint read FSlave write SetSlave;

    procedure DoLogMessage(const AMessage: String); virtual;
    procedure DoLogCallStack(const {%H-}Limit: Integer); virtual;
    procedure DoLogExpression(const {%H-}AnExpression: String); virtual; // implemented in TGDBMIBreakpoint
  end;
  TDBGBreakPointClass = class of TDBGBreakPoint;

  { TBaseBreakPoints }

  TBaseBreakPoints = class(TCollection)
  private
  protected
  public
    constructor Create(const ABreakPointClass: TBaseBreakPointClass);
    destructor Destroy; override;
    procedure Clear; reintroduce;
    function Add(const ASource: String; const ALine: Integer): TBaseBreakPoint; overload;
    function Add(const AAddress: TDBGPtr): TBaseBreakPoint; overload;
    function Add(const AData: String; const AScope: TDBGWatchPointScope;
                 const AKind: TDBGWatchPointKind): TBaseBreakPoint; overload;
    function Find(const ASource: String; const ALine: Integer): TBaseBreakPoint; overload;
    function Find(const ASource: String; const ALine: Integer; const AIgnore: TBaseBreakPoint): TBaseBreakPoint; overload;
    function Find(const AAddress: TDBGPtr): TBaseBreakPoint; overload;
    function Find(const AAddress: TDBGPtr; const AIgnore: TBaseBreakPoint): TBaseBreakPoint; overload;
    function Find(const AData: String; const AScope: TDBGWatchPointScope;
                  const AKind: TDBGWatchPointKind): TBaseBreakPoint; overload;
    function Find(const AData: String; const AScope: TDBGWatchPointScope;
                  const AKind: TDBGWatchPointKind; const AIgnore: TBaseBreakPoint): TBaseBreakPoint; overload;
    // no items property needed, it is "overridden" anyhow
  end;

  { TDBGBreakPoints }

  TDBGBreakPoints = class(TBaseBreakPoints)
  private
    FDebugger: TDebuggerIntf;  // reference to our debugger
    function GetItem(const AnIndex: Integer): TDBGBreakPoint;
    procedure SetItem(const AnIndex: Integer; const AValue: TDBGBreakPoint);
  protected
    procedure DoStateChange(const AOldState: TDBGState); virtual;
    property  Debugger: TDebuggerIntf read FDebugger write FDebugger;
  public
    constructor Create(const ADebugger: TDebuggerIntf;
                       const ABreakPointClass: TDBGBreakPointClass);
    function Add(const ASource: String; const ALine: Integer): TDBGBreakPoint; overload;
    function Add(const AAddress: TDBGPtr): TDBGBreakPoint; overload;
    function Add(const AData: String; const AScope: TDBGWatchPointScope;
                 const AKind: TDBGWatchPointKind): TDBGBreakPoint; overload;
    function Find(const ASource: String; const ALine: Integer): TDBGBreakPoint; overload;
    function Find(const ASource: String; const ALine: Integer; const AIgnore: TDBGBreakPoint): TDBGBreakPoint; overload;
    function Find(const AAddress: TDBGPtr): TDBGBreakPoint; overload;
    function Find(const AAddress: TDBGPtr; const {%H-}AIgnore: TDBGBreakPoint): TDBGBreakPoint; overload;
    function Find(const AData: String; const AScope: TDBGWatchPointScope;
                  const AKind: TDBGWatchPointKind): TDBGBreakPoint; overload;
    function Find(const AData: String; const AScope: TDBGWatchPointScope;
                  const AKind: TDBGWatchPointKind; const AIgnore: TDBGBreakPoint): TDBGBreakPoint; overload;

    property Items[const AnIndex: Integer]: TDBGBreakPoint read GetItem write SetItem; default;
  end;

{%endregion   ^^^^^  Breakpoints  ^^^^^   }

{$region Debug Info ***********************************************************}
(******************************************************************************)
(**                                                                          **)
(**   D E B U G   I N F O R M A T I O N                                      **)
(**                                                                          **)
(** Note: This part of the interface may/will still change.                  **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

  TDBGSymbolAttribute = (saRefParam,        // var, const, constref passed by reference
                         saInternalPointer, // PointerToObject
                         saArray, saDynArray
                        );
  TDBGSymbolAttributes = set of TDBGSymbolAttribute;
  TDBGFieldLocation = (flPrivate, flProtected, flPublic, flPublished);
  TDBGFieldFlag = (ffVirtual,ffConstructor,ffDestructor);
  TDBGFieldFlags = set of TDBGFieldFlag;

  TDBGType = class;

  TDBGValue = record
    AsString: ansistring;
    case integer of
      0: (As8Bits: BYTE);
      1: (As16Bits: WORD);
      2: (As32Bits: DWORD);
      3: (As64Bits: QWORD);
      4: (AsSingle: Single);
      5: (AsDouble: Double);
      6: (AsPointer: Pointer);
  end;

  { TDBGField }

  TDBGField = class(TObject)
  private
    FRefCount: Integer;
  protected
    FName: String;
    FFlags: TDBGFieldFlags;
    FLocation: TDBGFieldLocation;
    FDBGType: TDBGType;
    FClassName: String;
    procedure IncRefCount;
    procedure DecRefCount;
    property RefCount: Integer read FRefCount;
  public
    constructor Create(const AName: String; ADBGType: TDBGType;
                       ALocation: TDBGFieldLocation; AFlags: TDBGFieldFlags = [];
                       AClassName: String = '');
    destructor Destroy; override;
    property Name: String read FName;
    property DBGType: TDBGType read FDBGType;
    property Location: TDBGFieldLocation read FLocation;
    property Flags: TDBGFieldFlags read FFlags;
    property ClassName: String read FClassName; // the class in which the field was declared
  end;

  { TDBGFields }

  TDBGFields = class(TObject)
  private
    FList: TList;
    function GetField(const AIndex: Integer): TDBGField;
    function GetCount: Integer;
  protected
  public
    constructor Create;
    destructor Destroy; override;
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: TDBGField read GetField; default;
    procedure Add(const AField: TDBGField);
  end;

  TDBGTypes = class(TObject)
  private
    function GetType(const AIndex: Integer): TDBGType;
    function GetCount: Integer;
  protected
    FList: TList;
  public
    constructor Create;
    destructor Destroy; override;
    property Count: Integer read GetCount;
    property Items[const AIndex: Integer]: TDBGType read GetType; default;
  end;

  { TDBGType }

  TDBGType = class(TObject)
  private
    function GetFields: TDBGFields;
  protected
    FAncestor: String;
    FResult: TDBGType;
    FResultString: String;
    FArguments: TDBGTypes;
    FAttributes: TDBGSymbolAttributes;
    FFields: TDBGFields;
    FKind: TDBGSymbolKind;
    FMembers: TStrings;
    FTypeName: String;
    FTypeDeclaration: String;
    FDBGValue: TDBGValue;
    FBoundHigh: Integer;
    FBoundLow: Integer;
    FLen: Integer;
    procedure Init; virtual;
  public
    Value: TDBGValue;
    constructor Create(AKind: TDBGSymbolKind; const ATypeName: String);
    constructor Create(AKind: TDBGSymbolKind; const AArguments: TDBGTypes; AResult: TDBGType = nil);
    destructor Destroy; override;
    property Ancestor: String read FAncestor;
    property Arguments: TDBGTypes read FArguments;
    property Fields: TDBGFields read GetFields;
    property Kind: TDBGSymbolKind read FKind;
    property Attributes: TDBGSymbolAttributes read FAttributes;
    property TypeName: String read FTypeName;               // Name/Alias as in type section. One pascal token, or empty
    property TypeDeclaration: String read FTypeDeclaration; // Declaration (for array, set, enum, ..)
    property Members: TStrings read FMembers;               // Set & ENUM
    property Len: Integer read FLen;                        // Array
    property BoundLow: Integer read FBoundLow;              // Array
    property BoundHigh: Integer read FBoundHigh;            // Array
    property Result: TDBGType read FResult;
  end;

{%endregion   ^^^^^  Debug Info  ^^^^^   }

{%region Watches **************************************************************
 ******************************************************************************
 **                                                                          **
 **   W A T C H E S                                                          **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************}

  TWatchDisplayFormat =
    (wdfDefault,
     wdfStructure,
     wdfChar, wdfString,
     wdfDecimal, wdfUnsigned, wdfFloat, wdfHex,
     wdfPointer,
     wdfMemDump
    );

  TWatchBase = class;

  { TWatchValueBase }

  TWatchValueBase = class(TFreeNotifyingObject)
  protected
    function GetDisplayFormat: TWatchDisplayFormat; virtual; abstract;
    function GetEvaluateFlags: TDBGEvaluateFlags; virtual; abstract;
    function GetExpression: String; virtual; abstract;
    function GetRepeatCount: Integer; virtual; abstract;
    function GetStackFrame: Integer; virtual; abstract;
    function GetThreadId: Integer; virtual; abstract;
    function GetTypeInfo: TDBGType; virtual; abstract;
    function GetValidity: TDebuggerDataState; virtual; abstract;
    function GetValue: String; virtual; abstract;
    function GetWatchBase: TWatchBase; virtual; abstract;
    procedure SetTypeInfo(AValue: TDBGType); virtual; abstract;
    procedure SetValidity(AValue: TDebuggerDataState); virtual; abstract;
    procedure SetValue(AValue: String); virtual; abstract;
  public
    property DisplayFormat: TWatchDisplayFormat read GetDisplayFormat;
    property EvaluateFlags: TDBGEvaluateFlags read GetEvaluateFlags;
    property RepeatCount: Integer read GetRepeatCount;
    property ThreadId: Integer read GetThreadId;
    property StackFrame: Integer read GetStackFrame;
    property Expression: String read GetExpression;
    property Watch: TWatchBase read GetWatchBase;
  public
    property Validity: TDebuggerDataState read GetValidity write SetValidity;
    property Value: String read GetValue write SetValue;
    property TypeInfo: TDBGType read GetTypeInfo write SetTypeInfo;
  end;

  { TWatch }

  { TWatchBase }

  TWatchBase = class(TDelayedUdateItem)
  protected
    function GetDisplayFormat: TWatchDisplayFormat; virtual; abstract;
    function GetEnabled: Boolean; virtual; abstract;
    function GetEvaluateFlags: TDBGEvaluateFlags; virtual; abstract;
    function GetExpression: String; virtual; abstract;
    function GetRepeatCount: Integer; virtual; abstract;
    function GetValueBase(const AThreadId: Integer; const AStackFrame: Integer): TWatchValueBase; virtual; abstract;
    procedure SetDisplayFormat(AValue: TWatchDisplayFormat); virtual; abstract;
    procedure SetEnabled(AValue: Boolean); virtual; abstract;
    procedure SetEvaluateFlags(AValue: TDBGEvaluateFlags); virtual; abstract;
    procedure SetExpression(AValue: String); virtual; abstract;
    procedure SetRepeatCount(AValue: Integer); virtual; abstract;
  public
    procedure ClearValues; virtual; abstract;
  public
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property Expression: String read GetExpression write SetExpression;
    property DisplayFormat: TWatchDisplayFormat read GetDisplayFormat write SetDisplayFormat;
    property EvaluateFlags: TDBGEvaluateFlags read GetEvaluateFlags write SetEvaluateFlags;
    property RepeatCount: Integer read GetRepeatCount write SetRepeatCount;
    property Values[const AThreadId: Integer; const AStackFrame: Integer]: TWatchValueBase
             read GetValueBase;
  end;

  { TWatches }

  { TWatchesBase }

  TWatchesBase = class(TCollection)
  protected
    function GetItemBase(const AnIndex: Integer): TWatchBase;
    procedure SetItemBase(const AnIndex: Integer; const AValue: TWatchBase);
  public
    procedure ClearValues; virtual; abstract;
    function Find(const AExpression: String): TWatchBase; virtual; abstract;
    property Items[const AnIndex: Integer]: TWatchBase read GetItemBase write SetItemBase; default;
  end;

  { TWatchesSupplier }

  TWatchesSupplier = class(TDebuggerDataSupplier)
  private
    FCurrentWatches: TWatchesBase;
  protected
    procedure DoNewMonitor; override;
    procedure DoStateChange(const AOldState: TDBGState); override; // workaround for state changes during TWatchValue.GetValue
    procedure InternalRequestData(AWatchValue: TWatchValueBase); virtual;
  public
    constructor Create(const ADebugger: TDebuggerIntf);
    procedure RequestData(AWatchValue: TWatchValueBase);
    property CurrentWatches: TWatchesBase read FCurrentWatches write FCurrentWatches;
  end;

{%endregion   ^^^^^  Watches  ^^^^^   }

{%region Locals ***************************************************************
 ******************************************************************************
 **                                                                          **
 **   L O C A L S                                                            **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************}

    // TODO: a more watch-like value object

   { TLocalsValue }

   TLocalsValue = class(TDbgEntityValue)
   private
     FName: String;
     FValue: String;
   public
     procedure DoAssign(AnOther: TDbgEntityValue); override;
     property Name: String read FName;
     property Value: String read FValue;
   end;

 { TLocalsBase }

  TLocals = class(TDbgEntityValuesList)
  private
    function GetEntry(AnIndex: Integer): TLocalsValue;
    function GetName(const AnIndex: Integer): String;
    function GetValue(const AnIndex: Integer): String;
  protected
    function CreateEntry: TDbgEntityValue; override;
  public
    procedure Add(const AName, AValue: String);
    procedure SetDataValidity(AValidity: TDebuggerDataState); virtual; abstract;
  public
    function Count: Integer;reintroduce; virtual;
    property Entries[AnIndex: Integer]: TLocalsValue read GetEntry;
    property Names[const AnIndex: Integer]: String read GetName;
    property Values[const AnIndex: Integer]: String read GetValue;
  end;

  { TLocalsListBase }

  TLocalsList = class(TDbgEntitiesThreadStackList)
  private
    function GetEntry(AThreadId, AStackFrame: Integer): TLocals;
    function GetEntryByIdx(AnIndex: Integer): TLocals;
  protected
    //function CreateEntry(AThreadId, AStackFrame: Integer): TDbgEntityValuesList; override;
  public
    property EntriesByIdx[AnIndex: Integer]: TLocals read GetEntryByIdx;
    property Entries[AThreadId, AStackFrame: Integer]: TLocals read GetEntry; default;
  end;

  { TLocalsSupplier }

  TLocalsSupplier = class(TDebuggerDataSupplier)
  private
    FCurrentLocalsList: TLocalsList;
  protected
    procedure DoNewMonitor; override;
  public
    procedure RequestData(ALocals: TLocals); virtual;
    property  CurrentLocalsList: TLocalsList read FCurrentLocalsList write FCurrentLocalsList;
  end;

{%endregion   ^^^^^  Locals  ^^^^^   }

{%region Line Info ************************************************************
 ******************************************************************************
 **                                                                          **
 **   L I N E   I N F O                                                      **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************}

  TIDELineInfoEvent = procedure(const ASender: TObject; const ASource: String) of object;

  { TBaseLineInfo }

  TBaseLineInfo = class(TObject)
  protected
    function GetSource(const {%H-}AnIndex: integer): String; virtual;
  public
    constructor Create;
    function Count: Integer; virtual;
    function GetAddress(const {%H-}AIndex: Integer; const {%H-}ALine: Integer): TDbgPtr; virtual;
    function GetAddress(const ASource: String; const ALine: Integer): TDbgPtr;
    function GetInfo({%H-}AAdress: TDbgPtr; out {%H-}ASource, {%H-}ALine, {%H-}AOffset: Integer): Boolean; virtual;
    function IndexOf(const {%H-}ASource: String): integer; virtual;
    procedure Request(const {%H-}ASource: String); virtual;
    procedure Cancel(const {%H-}ASource: String); virtual;
  public
    property Sources[const AnIndex: Integer]: String read GetSource;
  end;

  { TDBGLineInfo }

  TDBGLineInfo = class(TBaseLineInfo)
  private
    FDebugger: TDebuggerIntf;  // reference to our debugger
    FOnChange: TIDELineInfoEvent;
  protected
    procedure Changed(ASource: String); virtual;
    procedure DoChange(ASource: String);
    procedure DoStateChange(const {%H-}AOldState: TDBGState); virtual;
    property Debugger: TDebuggerIntf read FDebugger write FDebugger;
  public
    constructor Create(const ADebugger: TDebuggerIntf);
    property OnChange: TIDELineInfoEvent read FOnChange write FOnChange;
  end;

{%endregion   ^^^^^  Line Info  ^^^^^   }

{%region Register *************************************************************
 ******************************************************************************
 **                                                                          **
 **   R E G I S T E R S                                                      **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************}

  TRegisterDisplayFormat =
    (rdDefault, rdHex, rdBinary, rdOctal, rdDecimal, rdRaw
    );

  TRegistersFormat = record
    Name: String;
    Format: TRegisterDisplayFormat;
  end;

  { TRegistersFormatList }

  TRegistersFormatList = class
  private
    FCount: integer;
    FFormats: array of TRegistersFormat;
    function GetFormat(AName: String): TRegisterDisplayFormat;
    procedure SetFormat(AName: String; AValue: TRegisterDisplayFormat);
  protected
    function IndexOf(const AName: String): integer;
    function Add(const AName: String; AFormat: TRegisterDisplayFormat): integer;
    property Count: Integer read FCount;
  public
    constructor Create;
    procedure Clear;
    property Format[AName: String]: TRegisterDisplayFormat read GetFormat write SetFormat; default;
  end;

  { TBaseRegisters }

  TBaseRegisters = class(TObject)
  protected
    FUpdateCount: Integer;
    FFormatList: TRegistersFormatList;
    function GetModified(const {%H-}AnIndex: Integer): Boolean; virtual;
    function GetName(const {%H-}AnIndex: Integer): String; virtual;
    function GetValue(const {%H-}AnIndex: Integer): String; virtual;
    function GetFormat(const AnIndex: Integer): TRegisterDisplayFormat;
    procedure SetFormat(const AnIndex: Integer; const AValue: TRegisterDisplayFormat); virtual;
    procedure ChangeUpdating; virtual;
    function  Updating: Boolean;
  public
    property FormatList: TRegistersFormatList read FFormatList write FFormatList;
  public
    constructor Create;
    function Count: Integer; virtual;
  public
    procedure BeginUpdate;
    procedure EndUpdate;
    property Modified[const AnIndex: Integer]: Boolean read GetModified;
    property Names[const AnIndex: Integer]: String read GetName;
    property Values[const AnIndex: Integer]: String read GetValue;
    property Formats[const AnIndex: Integer]: TRegisterDisplayFormat
             read GetFormat write SetFormat;
  end;

  { TDBGRegisters }

  TDBGRegisters = class(TBaseRegisters)
  private
    FDebugger: TDebuggerIntf;  // reference to our debugger
    FOnChange: TNotifyEvent;
    FChanged: Boolean;
  protected
    procedure Changed; virtual;
    procedure DoChange;
    procedure DoStateChange(const {%H-}AOldState: TDBGState); virtual;
    function GetCount: Integer; virtual;
    procedure ChangeUpdating; override;
    property Debugger: TDebuggerIntf read FDebugger write FDebugger;
  public
    procedure FormatChanged(const {%H-}AnIndex: Integer); virtual;
    function Count: Integer; override;
    constructor Create(const ADebugger: TDebuggerIntf);
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

{%endregion   ^^^^^  Register  ^^^^^   }

{%region Callstack ************************************************************
 ******************************************************************************
 **                                                                          **
 **   C A L L S T A C K                                                      **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************
 * The entries for the callstack are created on demand. This way when the     *
 * first entry is needed, it isn't required to create the whole stack         *
 *                                                                            *
 * TCallStackEntry needs to stay a readonly object so its data can be shared  *
 ******************************************************************************}

  { TCallStackEntry }

  { TCallStackEntryBase }

  TCallStackEntryBase = class(TObject)
  protected
    // for use in TThreadEntry ONLY
    function GetThreadId: Integer; virtual; abstract;
    function GetThreadName: String; virtual; abstract;
    function GetThreadState: String; virtual; abstract;
    procedure SetThreadState(AValue: String); virtual; abstract;
  protected
    function GetAddress: TDbgPtr; virtual; abstract;
    function GetArgumentCount: Integer; virtual; abstract;
    function GetArgumentName(const AnIndex: Integer): String; virtual; abstract;
    function GetArgumentValue(const AnIndex: Integer): String; virtual; abstract;
    function GetFunctionName: String; virtual; abstract;
    function GetIndex: Integer; virtual; abstract;
    function GetLine: Integer; virtual; abstract;
    function GetSource: String; virtual; abstract;
    function GetState: TDebuggerDataState; virtual; abstract;
    procedure SetState(AValue: TDebuggerDataState); virtual; abstract;
    //procedure ClearLocation; // TODO need a way to call Changed on TCallStack or TThreads // corrently done in SetThreadState
  public
    procedure Init(const AnAdress: TDbgPtr;
                   const AnArguments: TStrings; const AFunctionName: String;
                   const AUnitName, AClassName, AProcName, AFunctionArgs: String;
                   const ALine: Integer; AState: TDebuggerDataState = ddsValid); virtual; abstract;
    procedure Init(const AnAdress: TDbgPtr;
                   const AnArguments: TStrings; const AFunctionName: String;
                   const FileName, FullName: String;
                   const ALine: Integer; AState: TDebuggerDataState = ddsValid); virtual; abstract;
    function GetFunctionWithArg: String; virtual; abstract;
    //function IsCurrent: Boolean;
    //procedure MakeCurrent;
    property Address: TDbgPtr read GetAddress;
    property ArgumentCount: Integer read GetArgumentCount;
    property ArgumentNames[const AnIndex: Integer]: String read GetArgumentName;
    property ArgumentValues[const AnIndex: Integer]: String read GetArgumentValue;
    property FunctionName: String read GetFunctionName;
    property Index: Integer read GetIndex;
    property Line: Integer read GetLine;
    property Source: String read GetSource;
    property State: TDebuggerDataState read GetState write SetState;
  public
    // for use in TThreadEntry ONLY
    property ThreadId: Integer read GetThreadId;
    property ThreadName: String read GetThreadName;
    property ThreadState: String read GetThreadState write SetThreadState;
  end;

  { TCallStackBase }

  TCallStackBase = class(TFreeNotifyingObject)
  protected
    function GetNewCurrentIndex: Integer; virtual; abstract;
    function GetEntryBase(AIndex: Integer): TCallStackEntryBase; virtual; abstract;
    function GetThreadId: Integer; virtual; abstract;
    procedure SetThreadId(AValue: Integer); virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    procedure SetCount(AValue: Integer); virtual; abstract;
    function GetCurrent: Integer; virtual; abstract;
    procedure SetCurrent(AValue: Integer); virtual; abstract;
    function GetHighestUnknown: Integer; virtual;
    function GetLowestUnknown: Integer; virtual;
    function GetRawEntries: TMap; virtual; abstract;
  public
    procedure PrepareRange({%H-}AIndex, {%H-}ACount: Integer); virtual; abstract;
    procedure DoEntriesCreated; virtual; abstract;
    procedure DoEntriesUpdated; virtual; abstract;
    procedure SetCountValidity(AValidity: TDebuggerDataState); virtual; abstract;
    procedure SetHasAtLeastCountInfo(AValidity: TDebuggerDataState; AMinCount: Integer = -1); virtual; abstract;
    procedure SetCurrentValidity(AValidity: TDebuggerDataState); virtual; abstract;
    function CountLimited(ALimit: Integer): Integer; virtual; abstract;
    property Count: Integer read GetCount write SetCount;
    property CurrentIndex: Integer read GetCurrent write SetCurrent;
    property Entries[AIndex: Integer]: TCallStackEntryBase read GetEntryBase;
    property ThreadId: Integer read GetThreadId write SetThreadId;
    property NewCurrentIndex: Integer read GetNewCurrentIndex;

    property RawEntries: TMap read GetRawEntries;
    property LowestUnknown: Integer read GetLowestUnknown;
    property HighestUnknown: Integer read GetHighestUnknown;
  end;

  { TCallStackListBase }

  TCallStackListBase = class
  protected
    function GetEntryBase(const AIndex: Integer): TCallStackBase; virtual; abstract;
    function GetEntryForThreadBase(const AThreadId: Integer): TCallStackBase; virtual; abstract;
  public
    procedure Clear; virtual; abstract;
    function Count: Integer; virtual; abstract;   // Count of already requested CallStacks (via ThreadId)
    property Entries[const AIndex: Integer]: TCallStackBase read GetEntryBase; default;
    property EntriesForThreads[const AThreadId: Integer]: TCallStackBase read GetEntryForThreadBase;
  end;

  { TCallStackSupplier }

  TCallStackSupplier = class(TDebuggerDataSupplier)
  private
    FCurrentCallStackList: TCallStackListBase;
  protected
    procedure DoNewMonitor; override;
    //procedure CurrentChanged;
    procedure Changed;
  public
    procedure RequestCount(ACallstack: TCallStackBase); virtual;
    procedure RequestAtLeastCount(ACallstack: TCallStackBase; {%H-}ARequiredMinCount: Integer); virtual;
    procedure RequestCurrent(ACallstack: TCallStackBase); virtual;
    procedure RequestEntries(ACallstack: TCallStackBase); virtual;
    procedure UpdateCurrentIndex; virtual;
    property CurrentCallStackList: TCallStackListBase read FCurrentCallStackList write FCurrentCallStackList;
  end;

{%endregion   ^^^^^  Callstack  ^^^^^   }

{%region      *****  Disassembler  *****   }
(******************************************************************************)
(******************************************************************************)
(**                                                                          **)
(**   D I S A S S E M B L E R                                                **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

  PDisassemblerEntry = ^TDisassemblerEntry;
  TDisassemblerEntry = record
    Addr: TDbgPtr;                   // Address
    Dump: String;                    // Raw Data
    Statement: String;               // Asm
    FuncName: String;                // Function, if avail
    Offset: Integer;                 // Byte-Offest in Fonction
    SrcFileName: String;             // SrcFile if avail
    SrcFileLine: Integer;            // Line in SrcFile
    SrcStatementIndex: SmallInt;     // Index of Statement, within list of Stmnt of the same SrcLine
    SrcStatementCount: SmallInt;     // Count of Statements for this SrcLine
  end;

  { TBaseDisassembler }

  TBaseDisassembler = class(TObject)
  private
    FBaseAddr: TDbgPtr;
    FCountAfter: Integer;
    FCountBefore: Integer;
    FChangedLockCount: Integer;
    FIsChanged: Boolean;
    function GetEntryPtr(AIndex: Integer): PDisassemblerEntry;
    procedure IndexError(AIndex: Integer);
    function GetEntry(AIndex: Integer): TDisassemblerEntry;
  protected
    function  InternalGetEntry({%H-}AIndex: Integer): TDisassemblerEntry; virtual;
    function  InternalGetEntryPtr({%H-}AIndex: Integer): PDisassemblerEntry; virtual;
    procedure DoChanged; virtual;
    procedure Changed;
    procedure LockChanged;
    procedure UnlockChanged;
    procedure InternalIncreaseCountBefore(ACount: Integer);
    procedure InternalIncreaseCountAfter(ACount: Integer);
    procedure SetCountBefore(ACount: Integer);
    procedure SetCountAfter(ACount: Integer);
    procedure SetBaseAddr(AnAddr: TDbgPtr);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear; virtual;
    // Returns "True", if the range is valid, if not a ChangeNotification will be triggered later
    function PrepareRange({%H-}AnAddr: TDbgPtr; {%H-}ALinesBefore, {%H-}ALinesAfter: Integer): Boolean; virtual;
    property BaseAddr: TDbgPtr read FBaseAddr;
    property CountAfter: Integer read FCountAfter;
    property CountBefore: Integer read FCountBefore;
    property Entries[AIndex: Integer]: TDisassemblerEntry read GetEntry;
    property EntriesPtr[Index: Integer]: PDisassemblerEntry read GetEntryPtr;
  end;

  { TDBGDisassemblerEntryRange }

  TDBGDisassemblerEntryRange = class
  private
    FCount: Integer;
    FEntries: array of TDisassemblerEntry;
    FLastEntryEndAddr: TDBGPtr;
    FRangeEndAddr: TDBGPtr;
    FRangeStartAddr: TDBGPtr;
    function GetCapacity: Integer;
    function GetEntry(Index: Integer): TDisassemblerEntry;
    function GetEntryPtr(Index: Integer): PDisassemblerEntry;
    procedure SetCapacity(const AValue: Integer);
    procedure SetCount(const AValue: Integer);
  public
    procedure Clear;
    function Append(const AnEntryPtr: PDisassemblerEntry): Integer;
    procedure Merge(const AnotherRange: TDBGDisassemblerEntryRange);
    // Actual addresses on the ranges
    function FirstAddr: TDbgPtr;
    function LastAddr: TDbgPtr;
    function ContainsAddr(const AnAddr: TDbgPtr; IncludeNextAddr: Boolean = False): Boolean;
    function IndexOfAddr(const AnAddr: TDbgPtr): Integer;
    function IndexOfAddrWithOffs(const AnAddr: TDbgPtr): Integer;
    function IndexOfAddrWithOffs(const AnAddr: TDbgPtr; out AOffs: Integer): Integer;
    property Count: Integer read FCount write SetCount;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Entries[Index: Integer]: TDisassemblerEntry read GetEntry;
    property EntriesPtr[Index: Integer]: PDisassemblerEntry read GetEntryPtr;
    // The first address behind last entry
    property LastEntryEndAddr: TDBGPtr read FLastEntryEndAddr write FLastEntryEndAddr;
    // The addresses for which the range was requested
    // The range may bo more, than the entries, if there a gaps that cannot be retrieved.
    property RangeStartAddr: TDBGPtr read FRangeStartAddr write FRangeStartAddr;
    property RangeEndAddr: TDBGPtr read FRangeEndAddr write FRangeEndAddr;
  end;

  { TDBGDisassemblerEntryMap }

  TDBGDisassemblerEntryMapMergeEvent
    = procedure(MergeReceiver, MergeGiver: TDBGDisassemblerEntryRange) of object;

  { TDBGDisassemblerEntryMapIterator }
  TDBGDisassemblerEntryMap = class;

  TDBGDisassemblerEntryMapIterator = class(TMapIterator)
  public
    function GetRangeForAddr(AnAddr: TDbgPtr; IncludeNextAddr: Boolean = False): TDBGDisassemblerEntryRange;
    function NextRange: TDBGDisassemblerEntryRange;
    function PreviousRange: TDBGDisassemblerEntryRange;
  end;

  TDBGDisassemblerEntryMap = class(TMap)
  private
    FIterator: TDBGDisassemblerEntryMapIterator;
    FOnDelete: TNotifyEvent;
    FOnMerge: TDBGDisassemblerEntryMapMergeEvent;
    FFreeItemLock: Boolean;
  protected
    procedure ReleaseData(ADataPtr: Pointer); override;
  public
    constructor Create(AIdType: TMapIdType; ADataSize: Cardinal);
    destructor Destroy; override;
    // AddRange, may destroy the object
    procedure AddRange(const ARange: TDBGDisassemblerEntryRange); // Arange may be freed
    function GetRangeForAddr(AnAddr: TDbgPtr; IncludeNextAddr: Boolean = False): TDBGDisassemblerEntryRange;
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
    property OnMerge: TDBGDisassemblerEntryMapMergeEvent
             read FOnMerge write FOnMerge;
  end;

  { TDBGDisassembler }

  TDBGDisassembler = class(TBaseDisassembler)
  private
    FDebugger: TDebuggerIntf;
    FOnChange: TNotifyEvent;

    FEntryRanges: TDBGDisassemblerEntryMap;
    FCurrentRange: TDBGDisassemblerEntryRange;
    procedure EntryRangesOnDelete(Sender: TObject);
    procedure EntryRangesOnMerge(MergeReceiver, MergeGiver: TDBGDisassemblerEntryRange);
    function FindRange(AnAddr: TDbgPtr; ALinesBefore, ALinesAfter: Integer): Boolean;
  protected
    procedure DoChanged; override;
    procedure DoStateChange(const AOldState: TDBGState); virtual;
    function  InternalGetEntry(AIndex: Integer): TDisassemblerEntry; override;
    function  InternalGetEntryPtr(AIndex: Integer): PDisassemblerEntry; override;
    // PrepareEntries returns True, if it already added some entries
    function  PrepareEntries({%H-}AnAddr: TDbgPtr; {%H-}ALinesBefore, {%H-}ALinesAfter: Integer): boolean; virtual;
    function  HandleRangeWithInvalidAddr(ARange: TDBGDisassemblerEntryRange;{%H-}AnAddr:
                 TDbgPtr; var {%H-}ALinesBefore, {%H-}ALinesAfter: Integer): boolean; virtual;
    property Debugger: TDebuggerIntf read FDebugger write FDebugger;
    property EntryRanges: TDBGDisassemblerEntryMap read FEntryRanges;
  public
    constructor Create(const ADebugger: TDebuggerIntf);
    destructor Destroy; override;
    procedure Clear; override;
    function PrepareRange(AnAddr: TDbgPtr; ALinesBefore, ALinesAfter: Integer): Boolean; override;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

{%endregion   ^^^^^  Disassembler  ^^^^^   }

{%region Threads **************************************************************
 ******************************************************************************
 **                                                                          **
 **   T H R E A D S                                                          **
 **                                                                          **
 ******************************************************************************
 ******************************************************************************}

  { TThreadsBase }

  TThreadsBase = class(TObject)
  protected
    function GetEntryBase(const AnIndex: Integer): TCallStackEntryBase; virtual; abstract;
    function GetEntryByIdBase(const AnID: Integer): TCallStackEntryBase; virtual; abstract;
    function GetCurrentThreadId: Integer; virtual; abstract;
    procedure SetCurrentThreadId(AValue: Integer); virtual; abstract;
  public
    function Count: Integer; virtual; abstract;
    procedure Clear; virtual; abstract;
    procedure Add(AThread: TCallStackEntryBase); virtual; abstract;
    procedure Remove(AThread: TCallStackEntryBase); virtual; abstract;
    function  CreateEntry(const AIndex:Integer; const AnAdress: TDbgPtr;
                       const AnArguments: TStrings; const AFunctionName: String;
                       const FileName, FullName: String;
                       const ALine: Integer;
                       const AThreadId: Integer; const AThreadName: String;
                       const AThreadState: String;
                       AState: TDebuggerDataState = ddsValid): TCallStackEntryBase; virtual; abstract;
    procedure SetValidity(AValidity: TDebuggerDataState); virtual; abstract;
    property Entries[const AnIndex: Integer]: TCallStackEntryBase read GetEntryBase; default;
    property EntryById[const AnID: Integer]: TCallStackEntryBase read GetEntryByIdBase;
    property CurrentThreadId: Integer read GetCurrentThreadId write SetCurrentThreadId;
  end;

  { TThreadsSupplier }

  TThreadsSupplier = class(TDebuggerDataSupplier)
  private
    FCurrentThreads: TThreadsBase;
  protected
    procedure DoNewMonitor; override;
    procedure DoStateChange(const AOldState: TDBGState); override;
    procedure DoStateLeavePauseClean; override;
    procedure DoCleanAfterPause; virtual;
  public
    procedure RequestMasterData; virtual;
    procedure ChangeCurrentThread({%H-}ANewId: Integer); virtual;
    procedure Changed; // TODO: needed because entries can not notify the monitor
    property  CurrentThreads: TThreadsBase read FCurrentThreads write FCurrentThreads;
  end;

{%endregion   ^^^^^  Threads  ^^^^^   }

{%region Signals / Exceptions *************************************************}
(******************************************************************************)
(**                                                                          **)
(**   S I G N A L S  and  E X C E P T I O N S                                **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

  { TBaseSignal }

  TBaseSignal = class(TDelayedUdateItem)
  private
    FHandledByDebugger: Boolean;
    FID: Integer;
    FName: String;
    FResumeHandled: Boolean;
  protected
    procedure AssignTo(Dest: TPersistent); override;
    procedure SetHandledByDebugger(const AValue: Boolean); virtual;
    procedure SetID(const AValue: Integer); virtual;
    procedure SetName(const AValue: String); virtual;
    procedure SetResumeHandled(const AValue: Boolean); virtual;
  public
    constructor Create(ACollection: TCollection); override;
    property ID: Integer read FID write SetID;
    property Name: String read FName write SetName;
    property HandledByDebugger: Boolean read FHandledByDebugger write SetHandledByDebugger;
    property ResumeHandled: Boolean read FResumeHandled write SetResumeHandled;
  end;
  TBaseSignalClass = class of TBaseSignal;

  { TDBGSignal }

  TDBGSignal = class(TBaseSignal)
  private
    function GetDebugger: TDebuggerIntf;
  protected
    property Debugger: TDebuggerIntf read GetDebugger;
  public
  end;
  TDBGSignalClass = class of TDBGSignal;

  { TBaseSignals }
  TBaseSignals = class(TCollection)
  private
  protected
  public
    constructor Create(const AItemClass: TBaseSignalClass);
    procedure Reset; virtual;
    function Add(const AName: String; AID: Integer): TBaseSignal;
    function Find(const AName: String): TBaseSignal;
  end;

  { TDBGSignals }

  TDBGSignals = class(TBaseSignals)
  private
    FDebugger: TDebuggerIntf;  // reference to our debugger
    function GetItem(const AIndex: Integer): TDBGSignal;
    procedure SetItem(const AIndex: Integer; const AValue: TDBGSignal);
  protected
  public
    constructor Create(const ADebugger: TDebuggerIntf;
                       const ASignalClass: TDBGSignalClass);
    function Add(const AName: String; AID: Integer): TDBGSignal;
    function Find(const AName: String): TDBGSignal;
  public
    property Items[const AIndex: Integer]: TDBGSignal read GetItem
                                                      write SetItem; default;
  end;



  { TBaseException }
  TBaseException = class(TDelayedUdateItem)
  private
    procedure SetEnabled(AValue: Boolean);
  protected
    FEnabled: Boolean;
    FName: String;
    procedure AssignTo(Dest: TPersistent); override;
    procedure SetName(const AValue: String); virtual;
  public
    constructor Create(ACollection: TCollection); override;
  public
    property Name: String read FName write SetName;
    property Enabled: Boolean read FEnabled write SetEnabled; // ignored if enabled
  end;
  TBaseExceptionClass = class of TBaseException;

  { TDBGException }
  TDBGException = class(TBaseException)
  private
  protected
  public
  end;
  TDBGExceptionClass = class of TDBGException;

  { TBaseExceptions }
  TBaseExceptions = class(TCollection)
  private
    function GetItem(const AIndex: Integer): TBaseException;
    procedure SetItem(const AIndex: Integer; AValue: TBaseException);
  protected
    FIgnoreAll: Boolean;
    procedure AssignTo(Dest: TPersistent); override;
    procedure ClearExceptions; virtual;
    procedure SetIgnoreAll(const AValue: Boolean); virtual;
  public
    constructor Create(const AItemClass: TBaseExceptionClass);
    destructor Destroy; override;
    procedure Reset; virtual;
    function Add(const AName: String): TBaseException;
    function Find(const AName: String): TBaseException;
    property IgnoreAll: Boolean read FIgnoreAll write SetIgnoreAll;
    property Items[const AIndex: Integer]: TBaseException read GetItem
                                                        write SetItem; default;
  end;


{%endregion   ^^^^^  Signals / Exceptions  ^^^^^   }

(******************************************************************************)
(******************************************************************************)
(**                                                                          **)
(**   D E B U G G E R                                                        **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

  TDBGEventCategory = (
    ecBreakpoint, // Breakpoint hit
    ecProcess,    // Process start, process stop
    ecThread,     // Thread creation, destruction, start, etc.
    ecModule,     // Library load and unload
    ecOutput,     // DebugOutput calls
    ecWindows,    // Windows events
    ecDebugger);  // debugger errors and warnings
  TDBGEventCategories = set of TDBGEventCategory;

  TDBGEventType = (
    etDefault,
    // ecBreakpoint category
    etBreakpointEvaluation,
    etBreakpointHit,
    etBreakpointMessage,
    etBreakpointStackDump,
    etExceptionRaised,
    // ecModule category
    etModuleLoad,
    etModuleUnload,
    // ecOutput category
    etOutputDebugString,
    // ecProcess category
    etProcessExit,
    etProcessStart,
    // ecThread category
    etThreadExit,
    etThreadStart,
    // ecWindows category
    etWindowsMessagePosted,
    etWindowsMessageSent
  );

  TDBGFeedbackType = (ftInformation, ftWarning, ftError);
  TDBGFeedbackResult = (frOk, frStop);
  TDBGFeedbackResults = set of TDBGFeedbackResult;

  TDBGEventNotify = procedure(Sender: TObject;
                              const ACategory: TDBGEventCategory;
                              const AEventType: TDBGEventType;
                              const AText: String) of object;

  TDebuggerStateChangedEvent = procedure(ADebugger: TDebuggerIntf;
                                         AOldState: TDBGState) of object;
  TDebuggerBreakPointHitEvent = procedure(ADebugger: TDebuggerIntf; ABreakPoint: TBaseBreakPoint;
                                          var ACanContinue: Boolean) of object;
  TDBGOutputEvent = procedure(Sender: TObject; const AText: String) of object;
  TDBGCurrentLineEvent = procedure(Sender: TObject;
                                   const ALocation: TDBGLocationRec) of object;
  TDBGExceptionEvent = procedure(Sender: TObject; const AExceptionType: TDBGExceptionType;
                                 const AExceptionClass: String;
                                 const AExceptionLocation: TDBGLocationRec;
                                 const AExceptionText: String;
                                 out AContinue: Boolean) of object;

  TDBGFeedbackEvent = function(Sender: TObject; const AText, AInfo: String;
                               AType: TDBGFeedbackType; AButtons: TDBGFeedbackResults
                              ): TDBGFeedbackResult of object;


  TDebuggerNotifyReason = (dnrDestroy);

  { TDebuggerProperties }

  TDebuggerProperties = class(TPersistent)
  private
  public
    constructor Create; virtual;
    procedure Assign({%H-}Source: TPersistent); override;
  published
  end;
  TDebuggerPropertiesClass= class of TDebuggerProperties;


  TDebuggerIntf = class
  private
    FArguments: String;
    FBreakPoints: TDBGBreakPoints;
    FDebuggerEnvironment: TStrings;
    FCurEnvironment: TStrings;
    FDisassembler: TDBGDisassembler;
    FEnvironment: TStrings;
    FErrorStateInfo: String;
    FErrorStateMessage: String;
    FExceptions: TBaseExceptions;
    FExitCode: Integer;
    FExternalDebugger: String;
    FFileName: String;
    FLocals: TLocalsSupplier;
    FLineInfo: TDBGLineInfo;
    //FUnitInfoProvider, FInternalUnitInfoProvider: TDebuggerUnitInfoProvider;
    FOnBeforeState: TDebuggerStateChangedEvent;
    FOnConsoleOutput: TDBGOutputEvent;
    FOnFeedback: TDBGFeedbackEvent;
    FOnIdle: TNotifyEvent;
    FRegisters: TDBGRegisters;
    FShowConsole: Boolean;
    FSignals: TDBGSignals;
    FState: TDBGState;
    FCallStack: TCallStackSupplier;
    FWatches: TWatchesSupplier;
    FThreads: TThreadsSupplier;
    FOnCurrent: TDBGCurrentLineEvent;
    FOnException: TDBGExceptionEvent;
    FOnOutput: TDBGOutputEvent;
    FOnDbgOutput: TDBGOutputEvent;
    FOnDbgEvent: TDBGEventNotify;
    FOnState: TDebuggerStateChangedEvent;
    FOnBreakPointHit: TDebuggerBreakPointHitEvent;
    FWorkingDir: String;
    FDestroyNotificationList: array [TDebuggerNotifyReason] of TMethodList;
    procedure DebuggerEnvironmentChanged(Sender: TObject);
    procedure EnvironmentChanged(Sender: TObject);
    //function GetUnitInfoProvider: TDebuggerUnitInfoProvider;
    function  GetState: TDBGState;
    function  ReqCmd(const ACommand: TDBGCommand;
                     const AParams: array of const): Boolean;
    procedure SetDebuggerEnvironment (const AValue: TStrings );
    procedure SetEnvironment(const AValue: TStrings);
    procedure SetFileName(const AValue: String);
  protected
    procedure ResetStateToIdle; virtual;
    function  CreateBreakPoints: TDBGBreakPoints; virtual;
    function  CreateLocals: TLocalsSupplier; virtual;
    function  CreateLineInfo: TDBGLineInfo; virtual;
    function  CreateRegisters: TDBGRegisters; virtual;
    function  CreateCallStack: TCallStackSupplier; virtual;
    function  CreateDisassembler: TDBGDisassembler; virtual;
    function  CreateWatches: TWatchesSupplier; virtual;
    function  CreateThreads: TThreadsSupplier; virtual;
    function  CreateSignals: TDBGSignals; virtual;
    procedure DoCurrent(const ALocation: TDBGLocationRec);
    procedure DoDbgOutput(const AText: String);
    procedure DoDbgEvent(const ACategory: TDBGEventCategory; const AEventType: TDBGEventType; const AText: String);
    procedure DoException(const AExceptionType: TDBGExceptionType;
                          const AExceptionClass: String;
                          const AExceptionLocation: TDBGLocationRec;
                          const AExceptionText: String;
                          out AContinue: Boolean);
    procedure DoOutput(const AText: String);
    procedure DoBreakpointHit(const ABreakPoint: TBaseBreakPoint; var ACanContinue: Boolean);
    procedure DoBeforeState(const OldState: TDBGState); virtual;
    procedure DoState(const OldState: TDBGState); virtual;
    function  ChangeFileName: Boolean; virtual;
    function  GetCommands: TDBGCommands; virtual;
    function  GetSupportedCommands: TDBGCommands; virtual;
    function  GetTargetWidth: Byte; virtual;
    function  GetWaiting: Boolean; virtual;
    function  GetIsIdle: Boolean; virtual;
    function  RequestCommand(const ACommand: TDBGCommand;
                             const AParams: array of const): Boolean;
                             virtual; abstract; // True if succesful
    procedure SetExitCode(const AValue: Integer);
    procedure SetState(const AValue: TDBGState);
    procedure SetErrorState(const AMsg: String; const AInfo: String = '');
    procedure DoRelease; virtual;
  public
    class function Caption: String; virtual;         // The name of the debugger as shown in the debuggeroptions
    class function ExePaths: String; virtual;        // The default locations of the exe
    class function HasExePath: boolean; virtual;        // If the debugger needs to have an exe path

    // debugger properties
    class function CreateProperties: TDebuggerProperties; virtual;         // Creates debuggerproperties
    class function GetProperties: TDebuggerProperties;                     // Get the current properties
    class procedure SetProperties(const AProperties: TDebuggerProperties); // Set the current properties

    (* TODO:
       This method is a workaround for http://bugs.freepascal.org/view.php?id=21834
       See main.pp 12188 function TMainIDE.DoInitProjectRun: TModalResult;
       See debugmanager function TDebugManager.InitDebugger: Boolean;
       Checks could be performed in SetFileName, invalidating debuggerstate
       Errors should also be reported by debugger
    *)
    class function  RequiresLocalExecutable: Boolean; virtual;
  public
    constructor Create(const AExternalDebugger: String); virtual;
    destructor Destroy; override;

    procedure Init; virtual;                         // Initializes the debugger
    procedure Done; virtual;                         // Kills the debugger
    procedure Release;                               // Free/Destroy self
    procedure Run;                                   // Starts / continues debugging
    procedure Pause;                                 // Stops running
    procedure Stop;                                  // quit debugging
    procedure StepOver;
    procedure StepInto;
    procedure StepOverInstr;
    procedure StepIntoInstr;
    procedure StepOut;
    procedure RunTo(const ASource: String; const ALine: Integer);                // Executes til a certain point
    procedure JumpTo(const ASource: String; const ALine: Integer);               // No execute, only set exec point
    procedure Attach(AProcessID: String);
    procedure Detach;
    procedure SendConsoleInput(AText: String);
    function  Evaluate(const AExpression: String; var AResult: String;
                       var ATypeInfo: TDBGType;
                       EvalFlags: TDBGEvaluateFlags = []): Boolean;                     // Evaluates the given expression, returns true if valid
    function GetProcessList({%H-}AList: TRunningProcessInfoList): boolean; virtual;
    function  Modify(const AExpression, AValue: String): Boolean;                // Modifies the given expression, returns true if valid
    function  Disassemble(AAddr: TDbgPtr; ABackward: Boolean; out ANextAddr: TDbgPtr;
                          out ADump, AStatement, AFile: String; out ALine: Integer): Boolean; deprecated;
    function GetLocation: TDBGLocationRec; virtual;
    procedure LockCommandProcessing; virtual;
    procedure UnLockCommandProcessing; virtual;
    function  NeedReset: Boolean; virtual;
    procedure AddNotifyEvent(AReason: TDebuggerNotifyReason; AnEvent: TNotifyEvent);
    procedure RemoveNotifyEvent(AReason: TDebuggerNotifyReason; AnEvent: TNotifyEvent);
  public
    property Arguments: String read FArguments write FArguments;                 // Arguments feed to the program
    property BreakPoints: TDBGBreakPoints read FBreakPoints;                     // list of all breakpoints
    property CallStack: TCallStackSupplier read FCallStack;
    property Disassembler: TDBGDisassembler read FDisassembler;
    property Commands: TDBGCommands read GetCommands;                            // All current available commands of the debugger
    property DebuggerEnvironment: TStrings read FDebuggerEnvironment
                                           write SetDebuggerEnvironment;         // The environment passed to the debugger process
    property Environment: TStrings read FEnvironment write SetEnvironment;       // The environment passed to the debuggee
    property Exceptions: TBaseExceptions read FExceptions write FExceptions;      // A list of exceptions we should ignore
    property ExitCode: Integer read FExitCode;
    property ExternalDebugger: String read FExternalDebugger;                    // The name of the debugger executable
    property FileName: String read FFileName write SetFileName;                  // The name of the exe to be debugged
    property Locals: TLocalsSupplier read FLocals;                                    // list of all localvars etc
    property LineInfo: TDBGLineInfo read FLineInfo;                              // list of all source LineInfo
    property Registers: TDBGRegisters read FRegisters;                           // list of all registers
    property Signals: TDBGSignals read FSignals;                                 // A list of actions for signals we know
    property ShowConsole: Boolean read FShowConsole write FShowConsole;          // Indicates if the debugger should create a console for the debuggee
    property State: TDBGState read FState;                                       // The current state of the debugger
    property SupportedCommands: TDBGCommands read GetSupportedCommands;          // All available commands of the debugger
    property TargetWidth: Byte read GetTargetWidth;                              // Currently only 32 or 64
    property Waiting: Boolean read GetWaiting;                                   // Set when the debugger is wating for a command to complete
    property Watches: TWatchesSupplier read FWatches;                                 // list of all watches etc
    property Threads: TThreadsSupplier read FThreads;
    property WorkingDir: String read FWorkingDir write FWorkingDir;              // The working dir of the exe being debugged
    property IsIdle: Boolean read GetIsIdle;                                     // Nothing queued
    property ErrorStateMessage: String read FErrorStateMessage;
    property ErrorStateInfo: String read FErrorStateInfo;
    //property UnitInfoProvider: TDebuggerUnitInfoProvider                        // Provided by DebugBoss, to map files to packages or project
    //         read GetUnitInfoProvider write FUnitInfoProvider;
    // Events
    property OnCurrent: TDBGCurrentLineEvent read FOnCurrent write FOnCurrent;   // Passes info about the current line being debugged
    property OnDbgOutput: TDBGOutputEvent read FOnDbgOutput write FOnDbgOutput;  // Passes all debuggeroutput
    property OnDbgEvent: TDBGEventNotify read FOnDbgEvent write FOnDbgEvent;     // Passes recognized debugger events, like library load or unload
    property OnException: TDBGExceptionEvent read FOnException write FOnException;  // Fires when the debugger received an exeption
    property OnOutput: TDBGOutputEvent read FOnOutput write FOnOutput;           // Passes all output of the debugged target
    property OnBeforeState: TDebuggerStateChangedEvent read FOnBeforeState write FOnBeforeState;   // Fires when the current state of the debugger changes
    property OnState: TDebuggerStateChangedEvent read FOnState write FOnState;   // Fires when the current state of the debugger changes
    property OnBreakPointHit: TDebuggerBreakPointHitEvent read FOnBreakPointHit write FOnBreakPointHit;   // Fires when the program is paused at a breakpoint
    property OnConsoleOutput: TDBGOutputEvent read FOnConsoleOutput write FOnConsoleOutput;  // Passes Application Console Output
    property OnFeedback: TDBGFeedbackEvent read FOnFeedback write FOnFeedback;
    property OnIdle: TNotifyEvent read FOnIdle write FOnIdle;                    // Called if all outstanding requests are processed (queue empty)
  end;
  TDebuggerClass = class of TDebuggerIntf;

  TBaseDebugManagerIntf = class(TComponent)
  protected
    function GetDebuggerClass(const AIndex: Integer): TDebuggerClass;
    function FindDebuggerClass(const Astring: String): TDebuggerClass;
  public
    function DebuggerCount: Integer;
  end;

procedure RegisterDebugger(const ADebuggerClass: TDebuggerClass);

function dbgs(AState: TDBGState): String; overload;
function dbgs(ADataState: TDebuggerDataState): String; overload;
function dbgs(AKind: TDBGSymbolKind): String; overload;
function dbgs(AnAttribute: TDBGSymbolAttribute): String; overload;
function dbgs(AnAttributes: TDBGSymbolAttributes): String; overload;
function dbgs(ADisassRange: TDBGDisassemblerEntryRange): String; overload;
function dbgs(ACategory: TDBGEventCategory): String; overload;
function dbgs(AFlag: TDBGEvaluateFlag): String; overload;
function dbgs(AFlags: TDBGEvaluateFlags): String; overload;
function dbgs(AName: TDBGCommand): String; overload;

var
  DbgStateChangeCounter: Integer = 0;  // workaround for state changes during TWatchValue.GetValue

implementation

var
  DBG_STATE, DBG_EVENTS, DBG_STATE_EVENT, DBG_DATA_MONITORS,
  DBG_VERBOSE, DBG_WARNINGS, DBG_DISASSEMBLER: PLazLoggerLogGroup;

const
  COMMANDMAP: array[TDBGState] of TDBGCommands = (
  {dsNone } [],
  {dsIdle } [dcEnvironment],
  {dsStop } [dcRun, dcStepOver, dcStepInto, dcStepOverInstr, dcStepIntoInstr,
             dcAttach, dcBreak, dcWatch, dcEvaluate, dcEnvironment,
             dcSendConsoleInput],
  {dsPause} [dcRun, dcStop, dcStepOver, dcStepInto, dcStepOverInstr, dcStepIntoInstr,
             dcStepOut, dcRunTo, dcJumpto, dcDetach, dcBreak, dcWatch, dcLocal, dcEvaluate, dcModify,
             dcEnvironment, dcSetStackFrame, dcDisassemble, dcSendConsoleInput],
  {dsInternalPause} // same as run, so not really used
            [dcStop, dcBreak, dcWatch, dcEnvironment, dcSendConsoleInput],
  {dsInit } [],
  {dsRun  } [dcPause, dcStop, dcDetach, dcBreak, dcWatch, dcEnvironment, dcSendConsoleInput],
  {dsError} [dcStop],
  {dsDestroying} []
  );

var
  MDebuggerPropertiesList: TStringlist = nil;
  MDebuggerClasses: TStringList;

procedure RegisterDebugger(const ADebuggerClass: TDebuggerClass);
begin
  MDebuggerClasses.AddObject(ADebuggerClass.ClassName, TObject(Pointer(ADebuggerClass)));
end;

procedure DoFinalization;
var
  n: Integer;
begin
  if MDebuggerPropertiesList <> nil
  then begin
    for n := 0 to MDebuggerPropertiesList.Count - 1 do
      MDebuggerPropertiesList.Objects[n].Free;
    FreeAndNil(MDebuggerPropertiesList);
  end;
end;

function dbgs(AState: TDBGState): String; overload;
begin
  Result := '';
  WriteStr(Result, AState);
end;

function dbgs(ADataState: TDebuggerDataState): String;
begin
  writestr(Result{%H-}, ADataState);
end;

function dbgs(AKind: TDBGSymbolKind): String;
begin
  writestr(Result{%H-}, AKind);
end;

function dbgs(AnAttribute: TDBGSymbolAttribute): String;
begin
  writestr(Result{%H-}, AnAttribute);
end;

function dbgs(AnAttributes: TDBGSymbolAttributes): String;
var
  i: TDBGSymbolAttribute;
begin
  Result:='';
  for i := low(TDBGSymbolAttributes) to high(TDBGSymbolAttributes) do
    if i in AnAttributes then begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + dbgs(i);
    end;
  if Result <> '' then Result := '[' + Result + ']';
end;

function dbgs(ACategory: TDBGEventCategory): String;
begin
  writestr(Result{%H-}, ACategory);
end;

function dbgs(AFlag: TDBGEvaluateFlag): String;
begin
  Result := '';
  WriteStr(Result, AFlag);
end;

function dbgs(AFlags: TDBGEvaluateFlags): String;
var
  i: TDBGEvaluateFlag;
begin
  Result:='';
  for i := low(TDBGEvaluateFlags) to high(TDBGEvaluateFlags) do
    if i in AFlags then begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + dbgs(i);
    end;
  Result := '[' + Result + ']';
end;

function dbgs(AName: TDBGCommand): String;
begin
  Result := '';
  WriteStr(Result, AName);
end;

function dbgs(ADisassRange: TDBGDisassemblerEntryRange): String; overload;
var
  fo: Integer;
begin
  if (ADisassRange = nil)
  then begin
    Result := 'Range(nil)'
  end
  else begin
    if (ADisassRange.Count > 0)
    then fo := ADisassRange.EntriesPtr[0]^.Offset
    else fo := 0;
    {$PUSH}{$RANGECHECKS OFF}
    with ADisassRange do
      Result := Format('Range(%u)=[[ Cnt=%d, Capac=%d, [0].Addr=%u, RFirst=%u, [Cnt].Addr=%u, RLast=%u, REnd=%u, FirstOfs=%d ]]',
        [PtrUInt(ADisassRange), Count, Capacity, FirstAddr, RangeStartAddr, LastAddr, RangeEndAddr, LastEntryEndAddr, fo]);
    {$POP}
  end;
end;

{ TLocalsValue }

procedure TLocalsValue.DoAssign(AnOther: TDbgEntityValue);
begin
  inherited DoAssign(AnOther);
  FName := TLocalsValue(AnOther).FName;
  FValue := TLocalsValue(AnOther).FValue;
end;

{ TLocalsListBase }

function TLocalsList.GetEntry(AThreadId, AStackFrame: Integer): TLocals;
begin
  Result := TLocals(inherited Entries[AThreadId, AStackFrame]);
end;

function TLocalsList.GetEntryByIdx(AnIndex: Integer): TLocals;
begin
  Result := TLocals(inherited EntriesByIdx[AnIndex]);
end;

{ TLocalsBase }

function TLocals.GetEntry(AnIndex: Integer): TLocalsValue;
begin
  Result := TLocalsValue(inherited Entries[AnIndex]);
end;

function TLocals.GetName(const AnIndex: Integer): String;
begin
  Result := Entries[AnIndex].Name;
end;

function TLocals.GetValue(const AnIndex: Integer): String;
begin
  Result := Entries[AnIndex].Value;
end;

function TLocals.CreateEntry: TDbgEntityValue;
begin
  Result := TLocalsValue.Create;
end;

procedure TLocals.Add(const AName, AValue: String);
var
  v: TLocalsValue;
begin
  assert(not Immutable, 'TLocalsBase.Add Immutable');
  v := TLocalsValue(CreateEntry);
  v.FName := AName;
  v.FValue := AValue;
  inherited Add(v);
end;

function TLocals.Count: Integer;
begin
  Result := inherited Count;
end;

{ TWatchesBase }

function TWatchesBase.GetItemBase(const AnIndex: Integer): TWatchBase;
begin
  Result := TWatchBase(inherited Items[AnIndex]);
end;

procedure TWatchesBase.SetItemBase(const AnIndex: Integer; const AValue: TWatchBase);
begin
  inherited Items[AnIndex] := AValue;
end;

{ TCallStackBase }

function TCallStackBase.GetHighestUnknown: Integer;
begin
  Result := -1;
end;

function TCallStackBase.GetLowestUnknown: Integer;
begin
  Result := 0;
end;

{ TRunningProcessInfo }

constructor TRunningProcessInfo.Create(APID: Cardinal; const AImageName: string);
begin
  self.PID := APID;
  self.ImageName := AImageName;
end;

{ TDebuggerDataMonitor }

procedure TDebuggerDataMonitor.SetSupplier(const AValue: TDebuggerDataSupplier);
begin
  if FSupplier = AValue then exit;
  Assert((FSupplier=nil) or (AValue=nil), 'TDebuggerDataMonitor.Supplier already set');
  if FSupplier <> nil then FSupplier.Monitor := nil;
  FSupplier := AValue;
  if FSupplier <> nil then FSupplier.Monitor:= self;

  DoNewSupplier;
end;

procedure TDebuggerDataMonitor.DoModified;
begin
  //
end;

procedure TDebuggerDataMonitor.DoNewSupplier;
begin
  //
end;

procedure TDebuggerDataMonitor.DoStateChange(const AOldState, ANewState: TDBGState);
begin
  //
end;

destructor TDebuggerDataMonitor.Destroy;
begin
  Supplier := nil;
  inherited Destroy;
end;

{ TDebuggerDataSupplier }

procedure TDebuggerDataSupplier.SetMonitor(const AValue: TDebuggerDataMonitor);
begin
  if FMonitor = AValue then exit;
  Assert((FMonitor=nil) or (AValue=nil), 'TDebuggerDataSupplier.Monitor already set');
  FMonitor := AValue;
  DoNewMonitor;
end;

procedure TDebuggerDataSupplier.DoNewMonitor;
begin
  //
end;

procedure TDebuggerDataSupplier.DoStateEnterPause;
begin
  //
end;

procedure TDebuggerDataSupplier.DoStateLeavePause;
begin
  //
end;

procedure TDebuggerDataSupplier.DoStateLeavePauseClean;
begin
  DoStateLeavePause;
end;

procedure TDebuggerDataSupplier.DoStateChange(const AOldState: TDBGState);
begin
  if (Debugger = nil) then Exit;
  FNotifiedState := Debugger.State;
  FOldState := AOldState;
  DebugLnEnter(DBG_DATA_MONITORS, ['TDebuggerDataSupplier: >>ENTER: ', ClassName, '.DoStateChange  New-State=', dbgs(FNotifiedState)]);

  if FNotifiedState in [dsPause, dsInternalPause]
  then begin
    // typical: Clear and reload data
    if not(AOldState  in [dsPause, dsInternalPause] )
    then DoStateEnterPause;
  end
  else
  if (AOldState  in [dsPause, dsInternalPause, dsNone] )
  then begin
    // dsIdle happens after dsStop
    if (FNotifiedState  in [dsRun, dsInit, dsIdle]) or (AOldState = dsNone)
    then begin
      // typical: finalize snapshot and clear data.
      DoStateLeavePauseClean;
    end
    else begin
      // typical: finalize snapshot
      //          Do *not* clear data. Objects may be in use (e.g. dsError)
      DoStateLeavePause;
    end;
  end
  else
  if (AOldState  in [dsStop]) and (FNotifiedState = dsIdle)
  then begin
    // stopped // typical: finalize snapshot and clear data.
    DoStateLeavePauseClean;
  end;

  if Monitor <> nil then
    Monitor.DoStateChange(AOldState, FNotifiedState);
  DebugLnExit(DBG_DATA_MONITORS, ['TDebuggerDataSupplier: <<EXIT: ', ClassName, '.DoStateChange']);
end;

constructor TDebuggerDataSupplier.Create(const ADebugger: TDebuggerIntf);
begin
  FDebugger := ADebugger;
  inherited Create;
end;

destructor TDebuggerDataSupplier.Destroy;
begin
  if FMonitor <> nil then FMonitor.Supplier := nil;
  inherited Destroy;
end;

{ ===========================================================================
  TBaseBreakPoint
  =========================================================================== }

function TBaseBreakPoint.GetAddress: TDBGPtr;
begin
  Result := FAddress;
end;

function TBaseBreakPoint.GetKind: TDBGBreakPointKind;
begin
  Result := FKind;
end;

procedure TBaseBreakPoint.SetKind(const AValue: TDBGBreakPointKind);
begin
  if FKind <> AValue
  then begin
    FKind := AValue;
    DoKindChange;
  end;
end;

procedure TBaseBreakPoint.SetAddress(const AValue: TDBGPtr);
begin
  if FAddress <> AValue then
  begin
    FAddress := AValue;
    Changed;
  end;
end;

function TBaseBreakPoint.GetWatchData: String;
begin
  Result := FWatchData;
end;

function TBaseBreakPoint.GetWatchScope: TDBGWatchPointScope;
begin
  Result := FWatchScope;
end;

function TBaseBreakPoint.GetWatchKind: TDBGWatchPointKind;
begin
  Result := FWatchKind;
end;

procedure TBaseBreakPoint.AssignLocationTo(Dest: TPersistent);
var
  DestBreakPoint: TBaseBreakPoint absolute Dest;
begin
  DestBreakPoint.SetLocation(FSource, FLine);
end;

procedure TBaseBreakPoint.AssignTo(Dest: TPersistent);
var
  DestBreakPoint: TBaseBreakPoint absolute Dest;
begin
  // updatelock is set in source.assignto
  if Dest is TBaseBreakPoint
  then begin
    DestBreakPoint.SetKind(FKind);
    DestBreakPoint.SetWatch(FWatchData, FWatchScope, FWatchKind);
    DestBreakPoint.SetAddress(FAddress);
    AssignLocationTo(DestBreakPoint);
    DestBreakPoint.SetBreakHitCount(FBreakHitCount);
    DestBreakPoint.SetExpression(FExpression);
    DestBreakPoint.SetEnabled(FEnabled);
    DestBreakPoint.InitialEnabled := FInitialEnabled;
  end
  else inherited;
end;

constructor TBaseBreakPoint.Create(ACollection: TCollection);
begin
  FAddress := 0;
  FSource := '';
  FLine := -1;
  FValid := vsUnknown;
  FEnabled := False;
  FHitCount := 0;
  FBreakHitCount := 0;
  FExpression := '';
  FInitialEnabled := False;
  FKind := bpkSource;
  inherited Create(ACollection);
  AddReference;
end;

procedure TBaseBreakPoint.DoBreakHitCountChange;
begin
  Changed;
end;

procedure TBaseBreakPoint.DoEnableChange;
begin
  Changed;
end;

procedure TBaseBreakPoint.DoExpressionChange;
begin
  Changed;
end;

procedure TBaseBreakPoint.DoHit(const ACount: Integer; var AContinue: Boolean );
begin
  SetHitCount(ACount);
end;

function TBaseBreakPoint.GetBreakHitCount: Integer;
begin
  Result := FBreakHitCount;
end;

function TBaseBreakPoint.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

function TBaseBreakPoint.GetExpression: String;
begin
  Result := FExpression;
end;

function TBaseBreakPoint.GetHitCount: Integer;
begin
  Result := FHitCount;
end;

function TBaseBreakPoint.GetLine: Integer;
begin
  Result := FLine;
end;

function TBaseBreakPoint.GetSource: String;
begin
  Result := FSource;
end;

function TBaseBreakPoint.GetValid: TValidState;
begin
  Result := FValid;
end;

procedure TBaseBreakPoint.SetBreakHitCount(const AValue: Integer);
begin
  if FBreakHitCount <> AValue
  then begin
    FBreakHitCount := AValue;
    DoBreakHitCountChange;
  end;
end;

procedure TBaseBreakPoint.SetEnabled (const AValue: Boolean );
begin
  if FEnabled <> AValue
  then begin
    FEnabled := AValue;
    DoEnableChange;
  end;
end;

procedure TBaseBreakPoint.SetExpression (const AValue: String );
begin
  if FExpression <> AValue
  then begin
    FExpression := AValue;
    DoExpressionChange;
  end;
end;

procedure TBaseBreakPoint.SetHitCount (const AValue: Integer );
begin
  if FHitCount <> AValue
  then begin
    FHitCount := AValue;
    Changed;
  end;
end;

procedure TBaseBreakPoint.DoKindChange;
begin
  Changed;
end;

procedure TBaseBreakPoint.SetInitialEnabled(const AValue: Boolean);
begin
  if FInitialEnabled=AValue then exit;
  FInitialEnabled:=AValue;
end;

procedure TBaseBreakPoint.SetLocation (const ASource: String; const ALine: Integer );
begin
  if (FSource = ASource) and (FLine = ALine) then exit;
  FSource := ASource;
  FLine := ALine;
  Changed;
end;

procedure TBaseBreakPoint.SetWatch(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind);
begin
  if (AData = FWatchData) and (AScope = FWatchScope) and (AKind = FWatchKind) then exit;
  FWatchData := AData;
  FWatchScope := AScope;
  FWatchKind := AKind;
  Changed;
end;

procedure TBaseBreakPoint.SetValid(const AValue: TValidState );
begin
  if FValid <> AValue
  then begin
    FValid := AValue;
    Changed;
  end;
end;

{ =========================================================================== }
{ TDBGBreakPoint }
{ =========================================================================== }

constructor TDBGBreakPoint.Create (ACollection: TCollection );
begin
  FSlave := nil;
  inherited Create(ACollection);
end;

destructor TDBGBreakPoint.Destroy;
var
  SBP: TBaseBreakPoint;
begin
  SBP := FSlave;
  FSlave := nil;
  if SBP <> nil
  then SBP.DoChanged;   // In case UpdateCount  0

  inherited Destroy;
end;

procedure TDBGBreakPoint.Hit(var ACanContinue: Boolean);
var
  cnt: Integer;
begin
  cnt := HitCount + 1;
  if BreakHitcount > 0
  then ACanContinue := cnt < BreakHitcount;
  DoHit(cnt, ACanContinue);
  if Assigned(FSlave)
  then FSlave.DoHit(cnt, ACanContinue);
  Debugger.DoBreakpointHit(Self, ACanContinue)
end;

procedure TDBGBreakPoint.DoChanged;
begin
  inherited DoChanged;
  if FSlave <> nil
  then FSlave.Changed;
end;

procedure TDBGBreakPoint.DoStateChange(const AOldState: TDBGState);
begin
  if Debugger.State <> dsStop then Exit;
  if not (AOldState in [dsIdle, dsNone]) then Exit;

  BeginUpdate;
  try
    SetLocation(FSource, Line);
    Enabled := InitialEnabled;
    SetHitCount(0);
  finally
    EndUpdate;
  end;
end;

procedure TDBGBreakPoint.DoLogMessage(const AMessage: String);
begin
  Debugger.DoDbgEvent(ecBreakpoint, etBreakpointMessage, 'Breakpoint Message: ' + AMessage);
end;

procedure TDBGBreakPoint.DoLogCallStack(const Limit: Integer);
const
  Spacing = '    ';
var
  CallStack: TCallStackBase;
  I, Count: Integer;
  Entry: TCallStackEntryBase;
  StackString: String;
begin
  Debugger.SetState(dsInternalPause);
  CallStack := Debugger.CallStack.CurrentCallStackList.EntriesForThreads[Debugger.Threads.CurrentThreads.CurrentThreadId];
  if Limit = 0 then
  begin
    Debugger.DoDbgEvent(ecBreakpoint, etBreakpointMessage, 'Breakpoint Call Stack: Log all stack frames');
    Count := CallStack.Count;
    CallStack.PrepareRange(0, Count);
  end
  else
  begin
    Debugger.DoDbgEvent(ecBreakpoint, etBreakpointMessage, Format('Breakpoint Call Stack: Log %d stack frames', [Limit]));
    Count := CallStack.CountLimited(Limit);
    CallStack.PrepareRange(0, Count);
  end;

  for I := 0 to Count - 1 do
  begin
    Entry := CallStack.Entries[I];
    StackString := Spacing + Entry.Source;
    if Entry.Source = '' then // we do not have a source file => just show an adress
      StackString := Spacing + ':' + IntToHex(Entry.Address, 8);
    StackString := StackString + ' ' + Entry.GetFunctionWithArg;
    if line > 0 then
      StackString := StackString + ' line ' + IntToStr(Entry.Line);

    Debugger.DoDbgEvent(ecBreakpoint, etBreakpointStackDump, StackString);
  end;
end;

procedure TDBGBreakPoint.DoLogExpression(const AnExpression: String);
begin
  // will be called while Debgger.State = dsRun => can not call Evaluate
end;

function TDBGBreakPoint.GetDebugger: TDebuggerIntf;
begin
  Result := TDBGBreakPoints(Collection).FDebugger;
end;

procedure TDBGBreakPoint.SetSlave(const ASlave : TBaseBreakPoint);
begin
  Assert((FSlave = nil) or (ASlave = nil), 'TDBGBreakPoint.SetSlave already has a slave');
  FSlave := ASlave;
end;

procedure TDBGBreakPoint.SetEnabled(const AValue: Boolean);
begin
  if Enabled = AValue then exit;
  inherited SetEnabled(AValue);
  // feedback to IDEBreakPoint
  if FSlave <> nil then FSlave.Enabled := AValue;
end;

{ =========================================================================== }
{ TBaseBreakPoints }
{ =========================================================================== }

function TBaseBreakPoints.Add(const ASource: String; const ALine: Integer): TBaseBreakPoint;
begin
  Result := TBaseBreakPoint(inherited Add);
  Result.SetKind(bpkSource);
  Result.SetLocation(ASource, ALine);
end;

function TBaseBreakPoints.Add(const AAddress: TDBGPtr): TBaseBreakPoint;
begin
  Result := TBaseBreakPoint(inherited Add);
  Result.SetKind(bpkAddress);
  Result.SetAddress(AAddress);
end;

function TBaseBreakPoints.Add(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind): TBaseBreakPoint;
begin
  Result := TBaseBreakPoint(inherited Add);
  Result.SetKind(bpkData);
  Result.SetWatch(AData, AScope, AKind);
end;

constructor TBaseBreakPoints.Create(const ABreakPointClass: TBaseBreakPointClass);
begin
  inherited Create(ABreakPointClass);
end;

destructor TBaseBreakPoints.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TBaseBreakPoints.Clear;
begin
  while Count > 0 do TBaseBreakPoint(GetItem(0)).ReleaseReference;
end;

function TBaseBreakPoints.Find(const ASource: String; const ALine: Integer): TBaseBreakPoint;
begin
  Result := Find(ASource, ALine, nil);
end;

function TBaseBreakPoints.Find(const ASource: String; const ALine: Integer; const AIgnore: TBaseBreakPoint): TBaseBreakPoint;
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
  begin
    Result := TBaseBreakPoint(GetItem(n));
    if  (Result.Kind = bpkSource)
    and (Result.Line = ALine)
    and (AIgnore <> Result)
    and (CompareFilenames(Result.Source, ASource) = 0)
    then Exit;
  end;
  Result := nil;
end;

function TBaseBreakPoints.Find(const AAddress: TDBGPtr): TBaseBreakPoint;
begin
  Result := Find(AAddress, nil);
end;

function TBaseBreakPoints.Find(const AAddress: TDBGPtr; const AIgnore: TBaseBreakPoint): TBaseBreakPoint;
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
  begin
    Result := TBaseBreakPoint(GetItem(n));
    if  (Result.Kind = bpkAddress)
    and (Result.Address = AAddress)
    and (AIgnore <> Result)
    then Exit;
  end;
  Result := nil;
end;

function TBaseBreakPoints.Find(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind): TBaseBreakPoint;
begin
  Result := Find(AData, AScope, AKind, nil);
end;

function TBaseBreakPoints.Find(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind; const AIgnore: TBaseBreakPoint): TBaseBreakPoint;
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
  begin
    Result := TBaseBreakPoint(GetItem(n));
    if  (Result.Kind = bpkData)
    and (Result.WatchData = AData)
    and (Result.WatchScope = AScope)
    and (Result.WatchKind = AKind)
    and (AIgnore <> Result)
    then Exit;
  end;
  Result := nil;
end;

{ =========================================================================== }
{ TDBGBreakPoints }
{ =========================================================================== }

function TDBGBreakPoints.Add (const ASource: String; const ALine: Integer ): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Add(ASource, ALine));
end;

function TDBGBreakPoints.Add(const AAddress: TDBGPtr): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Add(AAddress));
end;

function TDBGBreakPoints.Add(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Add(AData, AScope, AKind));
end;

constructor TDBGBreakPoints.Create(const ADebugger: TDebuggerIntf;
  const ABreakPointClass: TDBGBreakPointClass);
begin
  FDebugger := ADebugger;
  inherited Create(ABreakPointClass);
end;

procedure TDBGBreakPoints.DoStateChange(const AOldState: TDBGState);
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
    GetItem(n).DoStateChange(AOldState);
end;

function TDBGBreakPoints.Find(const ASource: String; const ALine: Integer): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(Asource, ALine, nil));
end;

function TDBGBreakPoints.Find (const ASource: String; const ALine: Integer; const AIgnore: TDBGBreakPoint ): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(ASource, ALine, AIgnore));
end;

function TDBGBreakPoints.Find(const AAddress: TDBGPtr): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(AAddress));
end;

function TDBGBreakPoints.Find(const AAddress: TDBGPtr; const AIgnore: TDBGBreakPoint): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(AAddress, nil));
end;

function TDBGBreakPoints.Find(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(AData, AScope, AKind, nil));
end;

function TDBGBreakPoints.Find(const AData: String; const AScope: TDBGWatchPointScope;
  const AKind: TDBGWatchPointKind; const AIgnore: TDBGBreakPoint): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited Find(AData, AScope, AKind, AIgnore));
end;

function TDBGBreakPoints.GetItem (const AnIndex: Integer ): TDBGBreakPoint;
begin
  Result := TDBGBreakPoint(inherited GetItem(AnIndex));
end;

procedure TDBGBreakPoints.SetItem (const AnIndex: Integer; const AValue: TDBGBreakPoint );
begin
  inherited SetItem(AnIndex, AValue);
end;

{ TDBGField }

procedure TDBGField.IncRefCount;
begin
  inc(FRefCount);
end;

procedure TDBGField.DecRefCount;
begin
  dec(FRefCount);
  if FRefCount <= 0
  then Self.Free;
end;

constructor TDBGField.Create(const AName: String; ADBGType: TDBGType;
  ALocation: TDBGFieldLocation; AFlags: TDBGFieldFlags; AClassName: String = '');
begin
  inherited Create;
  FName := AName;
  FLocation := ALocation;
  FDBGType := ADBGType;
  FFlags := AFlags;
  FRefCount := 0;
  FClassName := AClassName;
end;

destructor TDBGField.Destroy;
begin
  FreeAndNil(FDBGType);
  inherited Destroy;
end;

{ TDBGFields }

constructor TDBGFields.Create;
begin
  FList := TList.Create;
  inherited;
end;

destructor TDBGFields.Destroy;
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
    Items[n].DecRefCount;

  FreeAndNil(FList);
  inherited;
end;

procedure TDBGFields.Add(const AField: TDBGField);
begin
  AField.IncRefCount;
  FList.Add(AField);
end;

function TDBGFields.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TDBGFields.GetField(const AIndex: Integer): TDBGField;
begin
  Result := TDBGField(FList[AIndex]);
end;

{ TDBGPTypes }

constructor TDBGTypes.Create;
begin
  FList := TList.Create;
  inherited;
end;

destructor TDBGTypes.Destroy;
var
  n: Integer;
begin
  for n := 0 to Count - 1 do
    Items[n].Free;

  FreeAndNil(FList);
  inherited;
end;

function TDBGTypes.GetCount: Integer;
begin
  Result := Flist.Count;
end;

function TDBGTypes.GetType(const AIndex: Integer): TDBGType;
begin
  Result := TDBGType(FList[AIndex]);
end;

{ TDBGPType }

function TDBGType.GetFields: TDBGFields;
begin
  if FFields = nil then
    FFields := TDBGFields.Create;
  Result := FFields;
end;

procedure TDBGType.Init;
begin
  //
end;

constructor TDBGType.Create(AKind: TDBGSymbolKind; const ATypeName: String);
begin
  FKind := AKind;
  FTypeName := ATypeName;
  Init;
  inherited Create;
end;

constructor TDBGType.Create(AKind: TDBGSymbolKind; const AArguments: TDBGTypes; AResult: TDBGType);
begin
  FKind := AKind;
  FArguments := AArguments;
  FResult := AResult;
  Init;
  inherited Create;
end;

destructor TDBGType.Destroy;
begin
  FreeAndNil(FResult);
  FreeAndNil(FArguments);
  FreeAndNil(FFields);
  FreeAndNil(FMembers);
  inherited;
end;

{ TWatchesSupplier }

procedure TWatchesSupplier.RequestData(AWatchValue: TWatchValueBase);
begin
  if FNotifiedState  in [dsPause, dsInternalPause]
  then InternalRequestData(AWatchValue)
  else AWatchValue.SetValidity(ddsInvalid);
end;

procedure TWatchesSupplier.DoNewMonitor;
begin
  inherited DoNewMonitor;
  FCurrentWatches := nil;
end;

procedure TWatchesSupplier.DoStateChange(const AOldState: TDBGState);
begin
  // workaround for state changes during TWatchValue.GetValue
  inc(DbgStateChangeCounter);
  if DbgStateChangeCounter = high(DbgStateChangeCounter) then DbgStateChangeCounter := 0;
  inherited DoStateChange(AOldState);
end;

procedure TWatchesSupplier.InternalRequestData(AWatchValue: TWatchValueBase);
begin
  AWatchValue.SetValidity(ddsInvalid);
end;

constructor TWatchesSupplier.Create(const ADebugger: TDebuggerIntf);
begin
  inherited Create(ADebugger);
  FNotifiedState := dsNone;
end;

{ TLocalsSupplier }

procedure TLocalsSupplier.DoNewMonitor;
begin
  inherited DoNewMonitor;
  FCurrentLocalsList := nil;
end;

procedure TLocalsSupplier.RequestData(ALocals: TLocals);
begin
  ALocals.SetDataValidity(ddsInvalid)
end;

{ TBaseLineInfo }

function TBaseLineInfo.GetSource(const AnIndex: integer): String;
begin
  Result := '';
end;

function TBaseLineInfo.IndexOf(const ASource: String): integer;
begin
  Result := -1;
end;

constructor TBaseLineInfo.Create;
begin
  inherited Create;
end;

function TBaseLineInfo.GetAddress(const AIndex: Integer; const ALine: Integer): TDbgPtr;
begin
  Result := 0;
end;

function TBaseLineInfo.GetAddress(const ASource: String; const ALine: Integer): TDbgPtr;
var
  idx: Integer;
begin
  idx := IndexOf(ASource);
  if idx = -1
  then Result := 0
  else Result := GetAddress(idx, ALine);
end;

function TBaseLineInfo.GetInfo(AAdress: TDbgPtr; out ASource, ALine, AOffset: Integer): Boolean;
begin
  Result := False;
end;

procedure TBaseLineInfo.Request(const ASource: String);
begin
end;

procedure TBaseLineInfo.Cancel(const ASource: String);
begin

end;

function TBaseLineInfo.Count: Integer;
begin
  Result := 0;
end;

{ TDBGLineInfo }

procedure TDBGLineInfo.Changed(ASource: String);
begin
  DoChange(ASource);
end;

procedure TDBGLineInfo.DoChange(ASource: String);
begin
  if Assigned(FOnChange) then FOnChange(Self, ASource);
end;

procedure TDBGLineInfo.DoStateChange(const AOldState: TDBGState);
begin
end;

constructor TDBGLineInfo.Create(const ADebugger: TDebuggerIntf);
begin
  inherited Create;
  FDebugger := ADebugger;
end;

{ TRegistersFormatList }

function TRegistersFormatList.GetFormat(AName: String): TRegisterDisplayFormat;
var
  i: Integer;
begin
  i := IndexOf(AName);
  if i < 0
  then Result := rdDefault
  else Result := FFormats[i].Format;
end;

procedure TRegistersFormatList.SetFormat(AName: String; AValue: TRegisterDisplayFormat);
var
  i: Integer;
begin
  i := IndexOf(AName);
  if i < 0
  then Add(AName, AValue)
  else FFormats[i].Format := AValue;
end;

function TRegistersFormatList.IndexOf(const AName: String): integer;
begin
  Result := FCount - 1;
  while Result >= 0 do begin
    if FFormats[Result].Name = AName then exit;
    dec(Result);
  end;
end;

function TRegistersFormatList.Add(const AName: String;
  AFormat: TRegisterDisplayFormat): integer;
begin
  if FCount >= length(FFormats) then SetLength(FFormats, Max(Length(FFormats)*2, 16));
  FFormats[FCount].Name := AName;
  FFormats[FCount].Format := AFormat;
  Result := FCount;
  inc(FCount);
end;

constructor TRegistersFormatList.Create;
begin
  FCount := 0;
end;

procedure TRegistersFormatList.Clear;
begin
  FCount := 0;
end;

{ =========================================================================== }
{ TBaseRegisters }
{ =========================================================================== }

function TBaseRegisters.Count: Integer;
begin
  Result := 0;
end;

procedure TBaseRegisters.BeginUpdate;
begin
  inc(FUpdateCount);
  if FUpdateCount = 1 then ChangeUpdating;
end;

procedure TBaseRegisters.EndUpdate;
begin
  dec(FUpdateCount);
  if FUpdateCount = 0 then ChangeUpdating;
end;

constructor TBaseRegisters.Create;
begin
  inherited Create;
  FormatList := nil;
end;

function TBaseRegisters.GetFormat(const AnIndex: Integer): TRegisterDisplayFormat;
var
  s: String;
begin
  Result := rdDefault;
  if FFormatList = nil then exit;
  s := Names[AnIndex];
  if s <> '' then
    Result := FFormatList[s];
end;

procedure TBaseRegisters.SetFormat(const AnIndex: Integer;
  const AValue: TRegisterDisplayFormat);
var
  s: String;
begin
  if FFormatList = nil then exit;
  s := Names[AnIndex];
  if s <> '' then
    FFormatList[s] := AValue;
end;

procedure TBaseRegisters.ChangeUpdating;
begin
  //
end;

function TBaseRegisters.Updating: Boolean;
begin
  Result := FUpdateCount <> 0;
end;

function TBaseRegisters.GetModified(const AnIndex: Integer): Boolean;
begin
  Result := False;
end;

function TBaseRegisters.GetName(const AnIndex: Integer): String;
begin
  Result := '';
end;

function TBaseRegisters.GetValue(const AnIndex: Integer): String;
begin
  Result := '';
end;

{ =========================================================================== }
{ TDBGRegisters }
{ =========================================================================== }

function TDBGRegisters.Count: Integer;
begin
  if  (FDebugger <> nil)
  and (FDebugger.State  in [dsPause, dsInternalPause])
  then Result := GetCount
  else Result := 0;
end;

constructor TDBGRegisters.Create(const ADebugger: TDebuggerIntf);
begin
  FChanged := False;
  inherited Create;
  FDebugger := ADebugger;
end;

procedure TDBGRegisters.DoChange;
begin
  if Updating then begin
    FChanged := True;
    exit;
  end;
  FChanged := False;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TDBGRegisters.DoStateChange(const AOldState: TDBGState);
begin
end;

procedure TDBGRegisters.FormatChanged(const AnIndex: Integer);
begin
  //
end;

procedure TDBGRegisters.Changed;
begin
  DoChange;
end;

function TDBGRegisters.GetCount: Integer;
begin
  Result := 0;
end;

procedure TDBGRegisters.ChangeUpdating;
begin
  inherited ChangeUpdating;
  if (not Updating) and FChanged then DoChange;
end;

{ =========================================================================== }
{ TCallStackSupplier }
{ =========================================================================== }

procedure TCallStackSupplier.Changed;
begin
  DebugLn(DBG_DATA_MONITORS, ['DebugDataMonitor: TCallStackSupplier.Changed']);
  Monitor.DoModified;
end;

procedure TCallStackSupplier.DoNewMonitor;
begin
  inherited DoNewMonitor;
  FCurrentCallStackList := nil;
end;

procedure TCallStackSupplier.RequestCount(ACallstack: TCallStackBase);
begin
  ACallstack.SetCountValidity(ddsInvalid);
end;

procedure TCallStackSupplier.RequestAtLeastCount(ACallstack: TCallStackBase;
  ARequiredMinCount: Integer);
begin
  RequestCount(ACallstack);
end;

procedure TCallStackSupplier.RequestCurrent(ACallstack: TCallStackBase);
begin
  ACallstack.SetCurrentValidity(ddsInvalid);
end;

procedure TCallStackSupplier.RequestEntries(ACallstack: TCallStackBase);
var
  e: TCallStackEntryBase;
  It: TMapIterator;
begin
  DebugLn(DBG_DATA_MONITORS, ['DebugDataMonitor: TCallStackSupplier.RequestEntries']);
  It := TMapIterator.Create(ACallstack.RawEntries);

  if not It.Locate(ACallstack.LowestUnknown )
  then if not It.EOM
  then It.Next;

  while (not IT.EOM) and (TCallStackEntryBase(It.DataPtr^).Index < ACallstack.HighestUnknown)
  do begin
    e := TCallStackEntryBase(It.DataPtr^);
    if e.State = ddsRequested then e.State := ddsInvalid;
    It.Next;
  end;
  It.Free;

  if Monitor <> nil
  then Monitor.DoModified;
end;

//procedure TCallStackSupplier.CurrentChanged;
//begin
//  DebugLn(DBG_DATA_MONITORS, ['DebugDataMonitor: TCallStackSupplier.CurrentChanged']);
//  if Monitor <> nil
//  then Monitor.NotifyCurrent;
//end;

procedure TCallStackSupplier.UpdateCurrentIndex;
begin
  //
end;

{ TThreadsSupplier }

procedure TThreadsSupplier.Changed;
begin
  if Monitor <> nil
  then Monitor.DoModified;
end;

procedure TThreadsSupplier.DoNewMonitor;
begin
  FCurrentThreads := nil;
end;

procedure TThreadsSupplier.ChangeCurrentThread(ANewId: Integer);
begin
  //
end;

procedure TThreadsSupplier.RequestMasterData;
begin
  //
end;

procedure TThreadsSupplier.DoStateChange(const AOldState: TDBGState);
begin
  if (Debugger.State = dsStop) and (CurrentThreads <> nil) then
    CurrentThreads.Clear;
  inherited DoStateChange(AOldState);
end;

procedure TThreadsSupplier.DoStateLeavePauseClean;
begin
  DoCleanAfterPause;
end;

procedure TThreadsSupplier.DoCleanAfterPause;
begin
  if FCurrentThreads <> nil then
    FCurrentThreads.Clear;
  if Monitor <> nil then
    Monitor.DoModified;
end;

{ =========================================================================== }
{ TBaseSignal }
{ =========================================================================== }

procedure TBaseSignal.AssignTo(Dest: TPersistent);
begin
  if Dest is TBaseSignal
  then begin
    TBaseSignal(Dest).Name := FName;
    TBaseSignal(Dest).ID := FID;
    TBaseSignal(Dest).HandledByDebugger := FHandledByDebugger;
    TBaseSignal(Dest).ResumeHandled := FResumeHandled;
  end
  else inherited AssignTo(Dest);
end;

constructor TBaseSignal.Create(ACollection: TCollection);
begin
  FID := 0;
  FHandledByDebugger := False;
  FResumeHandled := True;
  inherited Create(ACollection);
end;

procedure TBaseSignal.SetHandledByDebugger(const AValue: Boolean);
begin
  if AValue = FHandledByDebugger then Exit;
  FHandledByDebugger := AValue;
  Changed;
end;

procedure TBaseSignal.SetID (const AValue: Integer );
begin
  if FID = AValue then Exit;
  FID := AValue;
  Changed;
end;

procedure TBaseSignal.SetName (const AValue: String );
begin
  if FName = AValue then Exit;
  FName := AValue;
  Changed;
end;

procedure TBaseSignal.SetResumeHandled(const AValue: Boolean);
begin
  if FResumeHandled = AValue then Exit;
  FResumeHandled := AValue;
  Changed;
end;

{ =========================================================================== }
{ TDBGSignal }
{ =========================================================================== }

function TDBGSignal.GetDebugger: TDebuggerIntf;
begin
  Result := TDBGSignals(Collection).FDebugger;
end;

{ =========================================================================== }
{ TBaseSignals }
{ =========================================================================== }

function TBaseSignals.Add (const AName: String; AID: Integer ): TBaseSignal;
begin
  Result := TBaseSignal(inherited Add);
  Result.BeginUpdate;
  try
    Result.Name := AName;
    Result.ID := AID;
  finally
    Result.EndUpdate;
  end;
end;

constructor TBaseSignals.Create (const AItemClass: TBaseSignalClass );
begin
  inherited Create(AItemClass);
end;

procedure TBaseSignals.Reset;
begin
  Clear;
end;

function TBaseSignals.Find(const AName: String): TBaseSignal;
var
  n: Integer;
  S: String;
begin
  S := UpperCase(AName);
  for n := 0 to Count - 1 do
  begin
    Result := TBaseSignal(GetItem(n));
    if UpperCase(Result.Name) = S
    then Exit;
  end;
  Result := nil;
end;

{ =========================================================================== }
{ TDBGSignals }
{ =========================================================================== }

function TDBGSignals.Add(const AName: String; AID: Integer): TDBGSignal;
begin
  Result := TDBGSignal(inherited Add(AName, AID));
end;

constructor TDBGSignals.Create(const ADebugger: TDebuggerIntf;
  const ASignalClass: TDBGSignalClass);
begin
  FDebugger := ADebugger;
  inherited Create(ASignalClass);
end;

function TDBGSignals.Find(const AName: String): TDBGSignal;
begin
  Result := TDBGSignal(inherited Find(ANAme));
end;

function TDBGSignals.GetItem(const AIndex: Integer): TDBGSignal;
begin
  Result := TDBGSignal(inherited GetItem(AIndex));
end;

procedure TDBGSignals.SetItem(const AIndex: Integer; const AValue: TDBGSignal);
begin
  inherited SetItem(AIndex, AValue);
end;

{ =========================================================================== }
{ TBaseException }
{ =========================================================================== }

procedure TBaseException.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  Changed;
end;

procedure TBaseException.AssignTo(Dest: TPersistent);
begin
  if Dest is TBaseException
  then begin
    TBaseException(Dest).Name := FName;
  end
  else inherited AssignTo(Dest);
end;

constructor TBaseException.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
end;

procedure TBaseException.SetName(const AValue: String);
begin
  if FName = AValue then exit;

  if TBaseExceptions(GetOwner).Find(AValue) <> nil
  then raise EDBGExceptions.Create('Duplicate name: ' + AValue);

  FName := AValue;
  Changed;
end;

{ =========================================================================== }
{ TBaseExceptions }
{ =========================================================================== }

function TBaseExceptions.Add(const AName: String): TBaseException;
begin
  Result := TBaseException(inherited Add);
  Result.Name := AName;
end;

constructor TBaseExceptions.Create(const AItemClass: TBaseExceptionClass);
begin
  inherited Create(AItemClass);
  FIgnoreAll := False;
end;

destructor TBaseExceptions.Destroy;
begin
  ClearExceptions;
  inherited Destroy;
end;

procedure TBaseExceptions.Reset;
begin
  ClearExceptions;
  FIgnoreAll := False;
end;

function TBaseExceptions.Find(const AName: String): TBaseException;
var
  n: Integer;
  S: String;
begin
  S := UpperCase(AName);
  for n := 0 to Count - 1 do
  begin
    Result := TBaseException(GetItem(n));
    if UpperCase(Result.Name) = S
    then Exit;
  end;
  Result := nil;
end;

function TBaseExceptions.GetItem(const AIndex: Integer): TBaseException;
begin
  Result := TBaseException(inherited GetItem(AIndex));
end;

procedure TBaseExceptions.SetItem(const AIndex: Integer; AValue: TBaseException);
begin
  inherited SetItem(AIndex, AValue);
end;

procedure TBaseExceptions.ClearExceptions;
begin
  while Count>0 do
    TBaseException(GetItem(Count-1)).Free;
end;

procedure TBaseExceptions.SetIgnoreAll(const AValue: Boolean);
begin
  if FIgnoreAll = AValue then exit;
  FIgnoreAll := AValue;
  Changed;
end;

procedure TBaseExceptions.AssignTo(Dest: TPersistent);
begin
  if Dest is TBaseExceptions
  then begin
    TBaseExceptions(Dest).IgnoreAll := IgnoreAll;
  end
  else inherited AssignTo(Dest);
end;

{ TBaseDisassembler }

procedure TBaseDisassembler.IndexError(AIndex: Integer);
begin
  raise EInvalidOperation.CreateFmt('Index out of range (%d)', [AIndex]);
end;

function TBaseDisassembler.GetEntryPtr(AIndex: Integer): PDisassemblerEntry;
begin
  if (AIndex < -FCountBefore)
  or (AIndex >= FCountAfter) then IndexError(Aindex);

  Result := InternalGetEntryPtr(AIndex);
end;

function TBaseDisassembler.GetEntry(AIndex: Integer): TDisassemblerEntry;
begin
  if (AIndex < -FCountBefore)
  or (AIndex >= FCountAfter) then IndexError(Aindex);

  Result := InternalGetEntry(AIndex);
end;

function TBaseDisassembler.InternalGetEntry(AIndex: Integer): TDisassemblerEntry;
begin
  Result.Addr := 0;
  Result.Offset := 0;
  Result.SrcFileLine := 0;
  Result.SrcStatementIndex := 0;
  Result.SrcStatementCount := 0;
end;

function TBaseDisassembler.InternalGetEntryPtr(AIndex: Integer): PDisassemblerEntry;
begin
  Result := nil;
end;

procedure TBaseDisassembler.DoChanged;
begin
  // nothing
end;

procedure TBaseDisassembler.Changed;
begin
  if FChangedLockCount > 0
  then begin
    FIsChanged := True;
    exit;
  end;
  FIsChanged := False;
  DoChanged;
end;

procedure TBaseDisassembler.LockChanged;
begin
  inc(FChangedLockCount);
end;

procedure TBaseDisassembler.UnlockChanged;
begin
  dec(FChangedLockCount);
  if FIsChanged and (FChangedLockCount = 0)
  then Changed;
end;

procedure TBaseDisassembler.InternalIncreaseCountBefore(ACount: Integer);
begin
  // increase count withou change notification
  if ACount < FCountBefore
  then begin
    debugln(DBG_DISASSEMBLER, ['WARNING: TBaseDisassembler.InternalIncreaseCountBefore will decrease was ', FCountBefore , ' new=',ACount]);
    SetCountBefore(ACount);
  end
  else FCountBefore := ACount;
end;

procedure TBaseDisassembler.InternalIncreaseCountAfter(ACount: Integer);
begin
  // increase count withou change notification
  if ACount < FCountAfter
  then begin
    debugln(DBG_DISASSEMBLER, ['WARNING: TBaseDisassembler.InternalIncreaseCountAfter will decrease was ', FCountAfter , ' new=',ACount]);
    SetCountAfter(ACount)
  end
  else FCountAfter := ACount;
end;

procedure TBaseDisassembler.SetCountBefore(ACount: Integer);
begin
  if FCountBefore = ACount
  then exit;
  FCountBefore := ACount;
  Changed;
end;

procedure TBaseDisassembler.SetCountAfter(ACount: Integer);
begin
  if FCountAfter = ACount
  then exit;
  FCountAfter := ACount;
  Changed;
end;

procedure TBaseDisassembler.SetBaseAddr(AnAddr: TDbgPtr);
begin
  if FBaseAddr = AnAddr
  then exit;
  FBaseAddr := AnAddr;
  Changed;
end;

constructor TBaseDisassembler.Create;
begin
  Clear;
  FChangedLockCount := 0;
end;

destructor TBaseDisassembler.Destroy;
begin
  inherited Destroy;
  Clear;
end;

procedure TBaseDisassembler.Clear;
begin
  FCountAfter := 0;
  FCountBefore := 0;
  FBaseAddr := 0;
end;

function TBaseDisassembler.PrepareRange(AnAddr: TDbgPtr; ALinesBefore,
  ALinesAfter: Integer): Boolean;
begin
  Result := False;
end;

{ TDBGDisassemblerEntryRange }

function TDBGDisassemblerEntryRange.GetEntry(Index: Integer): TDisassemblerEntry;
begin
  if (Index < 0) or (Index >= FCount)
  then raise Exception.Create('Illegal Index');
  Result := FEntries[Index];
end;

function TDBGDisassemblerEntryRange.GetCapacity: Integer;
begin
  Result := length(FEntries);
end;

function TDBGDisassemblerEntryRange.GetEntryPtr(Index: Integer): PDisassemblerEntry;
begin
  if (Index < 0) or (Index >= FCount)
  then raise Exception.Create('Illegal Index');
  Result := @FEntries[Index];
end;

procedure TDBGDisassemblerEntryRange.SetCapacity(const AValue: Integer);
begin
  SetLength(FEntries, AValue);
  if FCount >= AValue
  then FCount := AValue - 1;
end;

procedure TDBGDisassemblerEntryRange.SetCount(const AValue: Integer);
begin
  if FCount = AValue then exit;
  if AValue >= Capacity
  then Capacity := AValue + Max(20, AValue div 4);

  FCount := AValue;
end;

procedure TDBGDisassemblerEntryRange.Clear;
begin
  SetCapacity(0);
  FCount := 0;
end;

function TDBGDisassemblerEntryRange.Append(const AnEntryPtr: PDisassemblerEntry): Integer;
begin
  if FCount >= Capacity
  then Capacity := FCount + Max(20, FCount div 4);

  FEntries[FCount] := AnEntryPtr^;
  Result := FCount;
  inc(FCount);
end;

procedure TDBGDisassemblerEntryRange.Merge(const AnotherRange: TDBGDisassemblerEntryRange);
var
  i, j: Integer;
  a: TDBGPtr;
begin
  if AnotherRange.RangeStartAddr < RangeStartAddr then
  begin
    // merge before
    i := AnotherRange.Count - 1;
    a := FirstAddr;
    while (i >= 0) and (AnotherRange.EntriesPtr[i]^.Addr >= a)
    do dec(i);
    inc(i);
    debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassemblerEntryRange.Merge: Merged to START:   Other=', dbgs(AnotherRange), '  To other index=', i, ' INTO self=', dbgs(self) ]);
    if Capacity < Count + i
    then Capacity := Count + i;
    for j := Count-1 downto 0 do
      FEntries[j+i] := FEntries[j];
    for j := 0 to i - 1 do
      FEntries[j] := AnotherRange.FEntries[j];
    FCount := FCount + i;
    FRangeStartAddr := AnotherRange.FRangeStartAddr;
  end
  else begin
    // merge after
    a:= LastAddr;
    i := 0;
    while (i < AnotherRange.Count) and (AnotherRange.EntriesPtr[i]^.Addr <= a)
    do inc(i);
    debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassemblerEntryRange.Merge to END:   Other=', dbgs(AnotherRange), '  From other index=', i, ' INTO self=', dbgs(self) ]);
    if Capacity < Count + AnotherRange.Count - i
    then Capacity := Count + AnotherRange.Count - i;
    for j := 0 to AnotherRange.Count - i - 1 do
      FEntries[Count + j] := AnotherRange.FEntries[i + j];
    FCount := FCount + AnotherRange.Count - i;
    FRangeEndAddr := AnotherRange.FRangeEndAddr;
    FLastEntryEndAddr := AnotherRange.FLastEntryEndAddr;
  end;
  debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassemblerEntryRange.Merge AFTER MERGE: ', dbgs(self) ]);
end;

function TDBGDisassemblerEntryRange.FirstAddr: TDbgPtr;
begin
  if FCount = 0
  then exit(0);
  Result := FEntries[0].Addr;
end;

function TDBGDisassemblerEntryRange.LastAddr: TDbgPtr;
begin
  if FCount = 0
  then exit(0);
  Result := FEntries[FCount-1].Addr;
end;

function TDBGDisassemblerEntryRange.ContainsAddr(const AnAddr: TDbgPtr;
  IncludeNextAddr: Boolean = False): Boolean;
begin
  if IncludeNextAddr
  then  Result := (AnAddr >= RangeStartAddr) and (AnAddr <= RangeEndAddr)
  else  Result := (AnAddr >= RangeStartAddr) and (AnAddr < RangeEndAddr);
end;

function TDBGDisassemblerEntryRange.IndexOfAddr(const AnAddr: TDbgPtr): Integer;
begin
  Result := FCount - 1;
  while Result >= 0 do begin
    if FEntries[Result].Addr = AnAddr
    then exit;
    dec(Result);
  end;
end;

function TDBGDisassemblerEntryRange.IndexOfAddrWithOffs(const AnAddr: TDbgPtr): Integer;
var
  O: Integer;
begin
  Result := IndexOfAddrWithOffs(AnAddr, O);
end;

function TDBGDisassemblerEntryRange.IndexOfAddrWithOffs(const AnAddr: TDbgPtr; out
  AOffs: Integer): Integer;
begin
  Result := FCount - 1;
  while Result >= 0 do begin
    if FEntries[Result].Addr <= AnAddr
    then break;
    dec(Result);
  end;
  If Result < 0
  then AOffs := 0
  else AOffs := AnAddr - FEntries[Result].Addr;
end;

{ TDBGDisassemblerEntryMapIterator }

function TDBGDisassemblerEntryMapIterator.GetRangeForAddr(AnAddr: TDbgPtr;
  IncludeNextAddr: Boolean): TDBGDisassemblerEntryRange;
begin
  Result := nil;
  if not Locate(AnAddr)
  then if not BOM
  then Previous;

  if BOM
  then exit;

  GetData(Result);
  if not Result.ContainsAddr(AnAddr, IncludeNextAddr)
  then Result := nil;
end;

function TDBGDisassemblerEntryMapIterator.NextRange: TDBGDisassemblerEntryRange;
begin
  Result := nil;
  if EOM
  then exit;

  Next;
  if not EOM
  then GetData(Result);
end;

function TDBGDisassemblerEntryMapIterator.PreviousRange: TDBGDisassemblerEntryRange;
begin
  Result := nil;
  if BOM
  then exit;

  Previous;
  if not BOM
  then GetData(Result);
end;

{ TDBGDisassemblerEntryMap }

procedure TDBGDisassemblerEntryMap.ReleaseData(ADataPtr: Pointer);
type
  PDBGDisassemblerEntryRange = ^TDBGDisassemblerEntryRange;
begin
  if FFreeItemLock
  then exit;
  if Assigned(FOnDelete)
  then FOnDelete(PDBGDisassemblerEntryRange(ADataPtr)^);
  PDBGDisassemblerEntryRange(ADataPtr)^.Free;
end;

constructor TDBGDisassemblerEntryMap.Create(AIdType: TMapIdType; ADataSize: Cardinal);
begin
  inherited;
  FIterator := TDBGDisassemblerEntryMapIterator.Create(Self);
end;

destructor TDBGDisassemblerEntryMap.Destroy;
begin
  FreeAndNil(FIterator);
  inherited Destroy;
end;

procedure TDBGDisassemblerEntryMap.AddRange(const ARange: TDBGDisassemblerEntryRange);
var
  MergeRng, MergeRng2: TDBGDisassemblerEntryRange;
  OldId: TDBGPtr;
begin
  debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassemblerEntryMap.AddRange ', dbgs(ARange), ' to map with count=', Count ]);
  if ARange.Count = 0 then begin
    ARange.Free;
    exit;
  end;

  MergeRng := GetRangeForAddr(ARange.RangeStartAddr, True);
  if MergeRng <> nil then begin
    // merge to end ( ARange.RangeStartAddr >= MergeRng.RangeStartAddr )
    // MergeRng keeps it's ID;
    MergeRng.Merge(ARange);
    if assigned(FOnMerge)
    then FOnMerge(MergeRng, ARange);
    ARange.Free;

    MergeRng2 := GetRangeForAddr(MergeRng.RangeEndAddr, True);
    if (MergeRng2 <> nil) and (MergeRng2 <> MergeRng) then begin
      // MergeRng is located before MergeRng2
      // MergeRng2 merges to end of MergeRng ( No ID changes )
      MergeRng.Merge(MergeRng2);
      if assigned(FOnMerge)
      then FOnMerge(MergeRng, MergeRng2);
      Delete(MergeRng2.RangeStartAddr);
    end;
    exit;
  end;

  MergeRng := GetRangeForAddr(ARange.RangeEndAddr, True);
  if MergeRng <> nil then begin
    // merge to start ( ARange.RangeEndAddr is in MergeRng )
    if MergeRng.ContainsAddr(ARange.RangeStartAddr)
    then begin
      debugln(['ERROR: New Range is completely inside existing ', dbgs(MergeRng)]);
      exit;
    end;
    // MergeRng changes ID
    OldId := MergeRng.RangeStartAddr;
    MergeRng.Merge(ARange);
    if assigned(FOnMerge)
    then FOnMerge(ARange, MergeRng);
    FFreeItemLock := True; // prevent destruction of MergeRng
    Delete(OldId);
    FFreeItemLock := False;
    Add(MergeRng.RangeStartAddr, MergeRng);
    ARange.Free;
    exit;
  end;

  Add(ARange.RangeStartAddr, ARange);
end;

function TDBGDisassemblerEntryMap.GetRangeForAddr(AnAddr: TDbgPtr;
  IncludeNextAddr: Boolean = False): TDBGDisassemblerEntryRange;
begin
  Result := FIterator.GetRangeForAddr(AnAddr, IncludeNextAddr);
end;

{ TDBGDisassembler }

procedure TDBGDisassembler.EntryRangesOnDelete(Sender: TObject);
begin
  if FCurrentRange <> Sender
  then exit;
  LockChanged;
  FCurrentRange := nil;
  SetBaseAddr(0);
  SetCountBefore(0);
  SetCountAfter(0);
  UnlockChanged;
end;

procedure TDBGDisassembler.EntryRangesOnMerge(MergeReceiver,
  MergeGiver: TDBGDisassemblerEntryRange);
var
  i: LongInt;
  lb, la: Integer;
begin
  // no need to call changed, will be done by whoever triggered this
  if FCurrentRange = MergeGiver
  then FCurrentRange := MergeReceiver;

  if FCurrentRange = MergeReceiver
  then begin
    i := FCurrentRange.IndexOfAddrWithOffs(BaseAddr);
    if i >= 0
    then begin
      InternalIncreaseCountBefore(i);
      InternalIncreaseCountAfter(FCurrentRange.Count - 1 - i);
      exit;
    end
    else if FCurrentRange.ContainsAddr(BaseAddr)
    then begin
      debugln(DBG_DISASSEMBLER, ['WARNING: TDBGDisassembler.OnMerge: Address at odd offset ',BaseAddr, ' before=',CountBefore, ' after=', CountAfter]);
      lb := CountBefore;
      la := CountAfter;
      if HandleRangeWithInvalidAddr(FCurrentRange, BaseAddr, lb, la)
      then begin
        InternalIncreaseCountBefore(lb);
        InternalIncreaseCountAfter(la);
        exit;
      end;
    end;

    LockChanged;
    SetBaseAddr(0);
    SetCountBefore(0);
    SetCountAfter(0);
    UnlockChanged;
  end;
end;

function TDBGDisassembler.FindRange(AnAddr: TDbgPtr; ALinesBefore,
  ALinesAfter: Integer): Boolean;
var
  i: LongInt;
  NewRange: TDBGDisassemblerEntryRange;
begin
  LockChanged;
  try
    Result := False;
    NewRange := FEntryRanges.GetRangeForAddr(AnAddr);

    if (NewRange <> nil)
    and ( (NewRange.RangeStartAddr > AnAddr) or (NewRange.RangeEndAddr < AnAddr) )
    then
      NewRange := nil;

    if NewRange = nil
    then begin
      debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.FindRange: Address not found ', AnAddr, ' wanted-before=',ALinesBefore,' wanted-after=',ALinesAfter,' in map with count=', FEntryRanges.Count ]);
      exit;
    end;

    i := NewRange.IndexOfAddr(AnAddr);
    if i < 0
    then begin
      // address at incorrect offset
      Result := HandleRangeWithInvalidAddr(NewRange, AnAddr, ALinesBefore, ALinesAfter);
      debugln(DBG_DISASSEMBLER, ['WARNING: TDBGDisassembler.FindRange: Address at odd offset ',AnAddr,'  Result=', dbgs(result), ' before=',CountBefore, ' after=', CountAfter, ' wanted-before=',ALinesBefore,' wanted-after=',ALinesAfter,' in map with count=', FEntryRanges.Count]);
      if Result
      then begin
        FCurrentRange := NewRange;
        SetBaseAddr(AnAddr);
        SetCountBefore(ALinesBefore);
        SetCountAfter(ALinesAfter);
      end;
      exit;
    end;

    FCurrentRange := NewRange;
    SetBaseAddr(AnAddr);
    SetCountBefore(i);
    SetCountAfter(NewRange.Count - 1 - i);
    Result := (i >= ALinesBefore) and (CountAfter >= ALinesAfter);
    debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.FindRange: Address found ',AnAddr,' Result=', dbgs(result), ' before=',CountBefore, ' after=', CountAfter, ' wanted-before=',ALinesBefore,' wanted-after=',ALinesAfter,' in map with count=', FEntryRanges.Count]);
  finally
    UnlockChanged;
  end;
end;

procedure TDBGDisassembler.DoChanged;
begin
  inherited DoChanged;
  if assigned(FOnChange)
  then FOnChange(Self);
end;

procedure TDBGDisassembler.Clear;
begin
  debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.Clear:  map had count=', FEntryRanges.Count ]);
  FCurrentRange := nil;
  FEntryRanges.Clear;
  inherited Clear;
  Changed;
end;

procedure TDBGDisassembler.DoStateChange(const AOldState: TDBGState);
begin
  if FDebugger.State = dsPause
  then begin
    Changed;
  end
  else begin
    if (AOldState = dsPause) or (AOldState = dsNone) { Force clear on initialisation }
    then Clear;
  end;
end;

function TDBGDisassembler.InternalGetEntry(AIndex: Integer): TDisassemblerEntry;
begin
  Result := FCurrentRange.Entries[AIndex + CountBefore];
end;

function TDBGDisassembler.InternalGetEntryPtr(AIndex: Integer): PDisassemblerEntry;
begin
  Result := FCurrentRange.EntriesPtr[AIndex + CountBefore];
end;

function TDBGDisassembler.PrepareEntries(AnAddr: TDbgPtr; ALinesBefore,
  ALinesAfter: Integer): boolean;
begin
  Result := False;
end;

function TDBGDisassembler.HandleRangeWithInvalidAddr(ARange: TDBGDisassemblerEntryRange;
  AnAddr: TDbgPtr; var ALinesBefore, ALinesAfter: Integer): boolean;
begin
  Result := False;
  if ARange <> nil then
    FEntryRanges.Delete(ARange.RangeStartAddr);
end;

constructor TDBGDisassembler.Create(const ADebugger: TDebuggerIntf);
begin
  FDebugger := ADebugger;
  FEntryRanges := TDBGDisassemblerEntryMap.Create(itu8, SizeOf(TDBGDisassemblerEntryRange));
  FEntryRanges.OnDelete   := @EntryRangesOnDelete;
  FEntryRanges.OnMerge   := @EntryRangesOnMerge;
  inherited Create;
end;

destructor TDBGDisassembler.Destroy;
begin
  inherited Destroy;
  FEntryRanges.OnDelete := nil;
  Clear;
  FreeAndNil(FEntryRanges);
end;

function TDBGDisassembler.PrepareRange(AnAddr: TDbgPtr; ALinesBefore,
  ALinesAfter: Integer): Boolean;
begin
  Result := False;
  if (Debugger = nil) or (Debugger.State <> dsPause) or (AnAddr = 0)
  then exit;
  if (ALinesBefore < 0) or (ALinesAfter < 0)
  then raise Exception.Create('invalid PrepareRange request');

  // Do not LockChange, if FindRange changes something, then notification must be send to syncronize counts on IDE-object
  Result:= FindRange(AnAddr, ALinesBefore, ALinesAfter);
  if result then debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.PrepareRange  found existing data  Addr=', AnAddr,' before=', ALinesBefore, ' After=', ALinesAfter ]);
  if Result
  then exit;

  if result then debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.PrepareRange  calling PrepareEntries Addr=', AnAddr,' before=', ALinesBefore, ' After=', ALinesAfter ]);
  if PrepareEntries(AnAddr, ALinesBefore, ALinesAfter)
  then Result:= FindRange(AnAddr, ALinesBefore, ALinesAfter);
  if result then debugln(DBG_DISASSEMBLER, ['INFO: TDBGDisassembler.PrepareRange  found data AFTER PrepareEntries Addr=', AnAddr,' before=', ALinesBefore, ' After=', ALinesAfter ]);
end;

(******************************************************************************)
(******************************************************************************)
(**                                                                          **)
(**   D E B U G G E R                                                        **)
(**                                                                          **)
(******************************************************************************)
(******************************************************************************)

{ TDebuggerProperties }

constructor TDebuggerProperties.Create;
begin
  //
end;

procedure TDebuggerProperties.Assign(Source: TPersistent);
begin
  //
end;

{ =========================================================================== }
{ TDebuggerIntf }
{ =========================================================================== }

class function TDebuggerIntf.Caption: String;
begin
  Result := 'No caption set';
end;

function TDebuggerIntf.ChangeFileName: Boolean;
begin
  Result := True;
end;

constructor TDebuggerIntf.Create(const AExternalDebugger: String);
var
  list: TStringList;
  nr: TDebuggerNotifyReason;
begin
  inherited Create;
  for nr := low(TDebuggerNotifyReason) to high(TDebuggerNotifyReason) do
    FDestroyNotificationList[nr] := TMethodList.Create;
  FOnState := nil;
  FOnCurrent := nil;
  FOnOutput := nil;
  FOnDbgOutput := nil;
  FState := dsNone;
  FArguments := '';
  FFilename := '';
  FExternalDebugger := AExternalDebugger;

  list := TStringList.Create;
  list.OnChange := @DebuggerEnvironmentChanged;
  FDebuggerEnvironment := list;

  list := TStringList.Create;
  list.OnChange := @EnvironmentChanged;
  FEnvironment := list;
  FCurEnvironment := TStringList.Create;
  //FInternalUnitInfoProvider := TDebuggerUnitInfoProvider.Create;

  FBreakPoints := CreateBreakPoints;
  FLocals := CreateLocals;
  FLineInfo := CreateLineInfo;
  FRegisters := CreateRegisters;
  FCallStack := CreateCallStack;
  FDisassembler := CreateDisassembler;
  FWatches := CreateWatches;
  FThreads := CreateThreads;
  FSignals := CreateSignals;
  FExitCode := 0;
end;

function TDebuggerIntf.CreateBreakPoints: TDBGBreakPoints;
begin
  Result := TDBGBreakPoints.Create(Self, TDBGBreakPoint);
end;

function TDebuggerIntf.CreateCallStack: TCallStackSupplier;
begin
  Result := TCallStackSupplier.Create(Self);
end;

function TDebuggerIntf.CreateDisassembler: TDBGDisassembler;
begin
  Result := TDBGDisassembler.Create(Self);
end;

function TDebuggerIntf.CreateLocals: TLocalsSupplier;
begin
  Result := TLocalsSupplier.Create(Self);
end;

function TDebuggerIntf.CreateLineInfo: TDBGLineInfo;
begin
  Result := TDBGLineInfo.Create(Self);
end;

class function TDebuggerIntf.CreateProperties: TDebuggerProperties;
begin
  Result := TDebuggerProperties.Create;
end;

function TDebuggerIntf.CreateRegisters: TDBGRegisters;
begin
  Result := TDBGRegisters.Create(Self);
end;

function TDebuggerIntf.CreateSignals: TDBGSignals;
begin
  Result := TDBGSignals.Create(Self, TDBGSignal);
end;

function TDebuggerIntf.CreateWatches: TWatchesSupplier;
begin
  Result := TWatchesSupplier.Create(Self);
end;

function TDebuggerIntf.CreateThreads: TThreadsSupplier;
begin
  Result := TThreadsSupplier.Create(Self);
end;

procedure TDebuggerIntf.DebuggerEnvironmentChanged (Sender: TObject );
begin
end;

destructor TDebuggerIntf.Destroy;
var
  nr: TDebuggerNotifyReason;
begin
  FDestroyNotificationList[dnrDestroy].CallNotifyEvents(Self);
  for nr := low(TDebuggerNotifyReason) to high(TDebuggerNotifyReason) do
    FreeAndNil(FDestroyNotificationList[nr]);
  // don't call events
  FOnState := nil;
  FOnCurrent := nil;
  FOnOutput := nil;
  FOnDbgOutput := nil;

  if FState <> dsNone
  then Done;

  FBreakPoints.Debugger := nil;
  FLocals.Debugger := nil;
  FLineInfo.Debugger := nil;
  FRegisters.Debugger := nil;
  FCallStack.Debugger := nil;
  FDisassembler.Debugger := nil;
  FWatches.Debugger := nil;
  FThreads.Debugger := nil;

  //FreeAndNil(FInternalUnitInfoProvider);
  FreeAndNil(FBreakPoints);
  FreeAndNil(FLocals);
  FreeAndNil(FLineInfo);
  FreeAndNil(FRegisters);
  FreeAndNil(FCallStack);
  FreeAndNil(FDisassembler);
  FreeAndNil(FWatches);
  FreeAndNil(FThreads);
  FreeAndNil(FDebuggerEnvironment);
  FreeAndNil(FEnvironment);
  FreeAndNil(FCurEnvironment);
  FreeAndNil(FSignals);
  inherited;
end;

function TDebuggerIntf.Disassemble(AAddr: TDbgPtr; ABackward: Boolean; out ANextAddr: TDbgPtr; out ADump, AStatement, AFile: String; out ALine: Integer): Boolean;
begin
  Result := ReqCmd(dcDisassemble, [AAddr, ABackward, @ANextAddr, @ADump, @AStatement, @AFile, @ALine]);
end;

function TDebuggerIntf.GetLocation: TDBGLocationRec;
begin
  Result.Address := 0;
  Result.SrcLine := 0;
end;

procedure TDebuggerIntf.LockCommandProcessing;
begin
  // nothing
end;

procedure TDebuggerIntf.UnLockCommandProcessing;
begin
  // nothing
end;

function TDebuggerIntf.NeedReset: Boolean;
begin
  Result := False;
end;

procedure TDebuggerIntf.AddNotifyEvent(AReason: TDebuggerNotifyReason; AnEvent: TNotifyEvent);
begin
  FDestroyNotificationList[AReason].Add(TMethod(AnEvent));
end;

procedure TDebuggerIntf.RemoveNotifyEvent(AReason: TDebuggerNotifyReason; AnEvent: TNotifyEvent);
begin
  FDestroyNotificationList[AReason].Remove(TMethod(AnEvent));
end;

procedure TDebuggerIntf.Done;
begin
  SetState(dsNone);
  FEnvironment.Clear;
  FCurEnvironment.Clear;
end;

procedure TDebuggerIntf.Release;
begin
  if Self <> nil
  then Self.DoRelease;
end;

procedure TDebuggerIntf.DoCurrent(const ALocation: TDBGLocationRec);
begin
  DebugLnEnter(DBG_EVENTS, ['DebugEvent: Enter >> DoCurrent (Location)  >>  State=', dbgs(FState)]);
  if Assigned(FOnCurrent) then FOnCurrent(Self, ALocation);
  DebugLnExit(DBG_EVENTS, ['DebugEvent: Exit  << DoCurrent (Location)  <<']);
end;

procedure TDebuggerIntf.DoDbgOutput(const AText: String);
begin
  // WriteLN(' [TDebuggerIntf] ', AText);
  if Assigned(FOnDbgOutput) then FOnDbgOutput(Self, AText);
end;

procedure TDebuggerIntf.DoDbgEvent(const ACategory: TDBGEventCategory; const AEventType: TDBGEventType; const AText: String);
begin
  DebugLnEnter(DBG_EVENTS, ['DebugEvent: Enter >> DoDbgEvent >>  State=', dbgs(FState), ' Category=', dbgs(ACategory)]);
  if Assigned(FOnDbgEvent) then FOnDbgEvent(Self, ACategory, AEventType, AText);
  DebugLnExit(DBG_EVENTS, ['DebugEvent: Exit  << DoDbgEvent <<']);
end;

procedure TDebuggerIntf.DoException(const AExceptionType: TDBGExceptionType;
  const AExceptionClass: String; const AExceptionLocation: TDBGLocationRec; const AExceptionText: String; out AContinue: Boolean);
begin
  DebugLnEnter(DBG_EVENTS, ['DebugEvent: Enter >> DoException >>  State=', dbgs(FState)]);
  if AExceptionType = deInternal then
    DoDbgEvent(ecDebugger, etExceptionRaised,
               Format('Exception class "%s" at $%.' + IntToStr(TargetWidth div 4) + 'x with message "%s"',
                      [AExceptionClass, AExceptionLocation.Address, AExceptionText]));
  if Assigned(FOnException) then
    FOnException(Self, AExceptionType, AExceptionClass, AExceptionLocation, AExceptionText, AContinue)
  else
    AContinue := True;
  DebugLnExit(DBG_EVENTS, ['DebugEvent: Exit  << DoException <<']);
end;

procedure TDebuggerIntf.DoOutput(const AText: String);
begin
  if Assigned(FOnOutput) then FOnOutput(Self, AText);
end;

procedure TDebuggerIntf.DoBreakpointHit(const ABreakPoint: TBaseBreakPoint; var ACanContinue: Boolean);
begin
  DebugLnEnter(DBG_EVENTS, ['DebugEvent: Enter >> DoBreakpointHit <<  State=', dbgs(FState)]);
  if Assigned(FOnBreakpointHit)
  then FOnBreakpointHit(Self, ABreakPoint, ACanContinue);
  DebugLnExit(DBG_EVENTS, ['DebugEvent: Exit  >> DoBreakpointHit <<']);
end;

procedure TDebuggerIntf.DoBeforeState(const OldState: TDBGState);
begin
  DebugLnEnter(DBG_STATE_EVENT, ['DebugEvent: Enter >> DoBeforeState <<  State=', dbgs(FState)]);
  if Assigned(FOnBeforeState) then FOnBeforeState(Self, OldState);
  DebugLnExit(DBG_STATE_EVENT, ['DebugEvent: Exit  >> DoBeforeState <<']);
end;

procedure TDebuggerIntf.DoState(const OldState: TDBGState);
begin
  DebugLnEnter(DBG_STATE_EVENT, ['DebugEvent: Enter >> DoState <<  State=', dbgs(FState)]);
  if Assigned(FOnState) then FOnState(Self, OldState);
  DebugLnExit(DBG_STATE_EVENT, ['DebugEvent: Exit  >> DoState <<']);
end;

procedure TDebuggerIntf.EnvironmentChanged(Sender: TObject);
var
  n, idx: integer;
  S: String;
  Env: TStringList;
begin
  // Createe local copy
  if FState <> dsNone then
  begin
    Env := TStringList.Create;
    try
      Env.Assign(Environment);

      // Check for nonexisting and unchanged vars
      for n := 0 to FCurEnvironment.Count - 1 do
      begin
        S := FCurEnvironment[n];
        idx := Env.IndexOfName(GetPart([], ['='], S, False, False));
        if idx = -1
        then ReqCmd(dcEnvironment, [S, False])
        else begin
          if Env[idx] = S
          then Env.Delete(idx);
        end;
      end;

      // Set the remaining
      for n := 0 to Env.Count - 1 do
      begin
        S := Env[n];
        //Skip functions etc.
        if Pos('=()', S) <> 0 then Continue;
        ReqCmd(dcEnvironment, [S, True]);
      end;
    finally
      Env.Free;
    end;
  end;
  FCurEnvironment.Assign(FEnvironment);
end;

//function TDebuggerIntf.GetUnitInfoProvider: TDebuggerUnitInfoProvider;
//begin
//  Result := FUnitInfoProvider;
//  if Result = nil then
//    Result := FInternalUnitInfoProvider;
//end;

function TDebuggerIntf.GetIsIdle: Boolean;
begin
  Result := False;
end;

function TDebuggerIntf.Evaluate(const AExpression: String; var AResult: String;
  var ATypeInfo: TDBGType; EvalFlags: TDBGEvaluateFlags = []): Boolean;
begin
  FreeAndNIL(ATypeInfo);
  Result := ReqCmd(dcEvaluate, [AExpression, @AResult, @ATypeInfo, Integer(EvalFlags)]);
end;

function TDebuggerIntf.GetProcessList(AList: TRunningProcessInfoList): boolean;
begin
  result := false;
end;

class function TDebuggerIntf.ExePaths: String;
begin
  Result := '';
end;

class function TDebuggerIntf.HasExePath: boolean;
begin
  Result := true; // most debugger are external and have an exe path
end;

function TDebuggerIntf.GetCommands: TDBGCommands;
begin
  Result := COMMANDMAP[State] * GetSupportedCommands;
end;

class function TDebuggerIntf.GetProperties: TDebuggerProperties;
var
  idx: Integer;
begin
  if MDebuggerPropertiesList = nil
  then MDebuggerPropertiesList := TStringList.Create;
  idx := MDebuggerPropertiesList.IndexOf(ClassName);
  if idx = -1
  then begin
    Result := CreateProperties;
    MDebuggerPropertiesList.AddObject(ClassName, Result)
  end
  else begin
    Result := TDebuggerProperties(MDebuggerPropertiesList.Objects[idx]);
  end;
end;

function TDebuggerIntf.GetState: TDBGState;
begin
  Result := FState;
end;

function TDebuggerIntf.GetSupportedCommands: TDBGCommands;
begin
  Result := [];
end;

function TDebuggerIntf.GetTargetWidth: Byte;
begin
  Result := SizeOf(PtrInt)*8;
end;

function TDebuggerIntf.GetWaiting: Boolean;
begin
  Result := False;
end;

procedure TDebuggerIntf.Init;
begin
  FExitCode := 0;
  FErrorStateMessage := '';
  FErrorStateInfo := '';
  SetState(dsIdle);
end;

procedure TDebuggerIntf.JumpTo(const ASource: String; const ALine: Integer);
begin
  ReqCmd(dcJumpTo, [ASource, ALine]);
end;

procedure TDebuggerIntf.Attach(AProcessID: String);
begin
  if State = dsIdle then SetState(dsStop);  // Needed, because no filename was set
  ReqCmd(dcAttach, [AProcessID]);
end;

procedure TDebuggerIntf.Detach;
begin
  ReqCmd(dcDetach, []);
end;

procedure TDebuggerIntf.SendConsoleInput(AText: String);
begin
  ReqCmd(dcSendConsoleInput, [AText]);
end;

function TDebuggerIntf.Modify(const AExpression, AValue: String): Boolean;
begin
  Result := ReqCmd(dcModify, [AExpression, AValue]);
end;

procedure TDebuggerIntf.Pause;
begin
  ReqCmd(dcPause, []);
end;

function TDebuggerIntf.ReqCmd(const ACommand: TDBGCommand;
  const AParams: array of const): Boolean;
begin
  if FState = dsNone then Init;
  if ACommand in Commands
  then begin
    Result := RequestCommand(ACommand, AParams);
    if not Result then begin
      DebugLn(DBG_WARNINGS, 'TDebuggerIntf.ReqCmd failed: ',dbgs(ACommand));
    end;
  end
  else begin
    DebugLn(DBG_WARNINGS, 'TDebuggerIntf.ReqCmd Command not supported: ',
            dbgs(ACommand),' ClassName=',ClassName);
    Result := False;
  end;
end;

procedure TDebuggerIntf.Run;
begin
  ReqCmd(dcRun, []);
end;

procedure TDebuggerIntf.RunTo(const ASource: String; const ALine: Integer);
begin
  ReqCmd(dcRunTo, [ASource, ALine]);
end;

procedure TDebuggerIntf.SetDebuggerEnvironment (const AValue: TStrings );
begin
  FDebuggerEnvironment.Assign(AValue);
end;

procedure TDebuggerIntf.SetEnvironment(const AValue: TStrings);
begin
  FEnvironment.Assign(AValue);
end;

procedure TDebuggerIntf.SetExitCode(const AValue: Integer);
begin
  FExitCode := AValue;
end;

procedure TDebuggerIntf.SetFileName(const AValue: String);
begin
  if FFileName <> AValue
  then begin
    DebugLn(DBG_VERBOSE, '[TDebuggerIntf.SetFileName] "', AValue, '"');
    if FState in [dsRun, dsPause]
    then begin
      Stop;
      // check if stopped
      if FState <> dsStop
      then SetState(dsError);
    end;

    if FState = dsStop
    then begin
      // Reset state
      FFileName := '';
      ResetStateToIdle;
      ChangeFileName;
    end;

    FFileName := AValue;
    // TODO: Why?
    if  (FFilename <> '') and (FState = dsIdle) and ChangeFileName
    then SetState(dsStop);
  end
  else
  if FileName = '' then
    ResetStateToIdle;
end;

procedure TDebuggerIntf.ResetStateToIdle;
begin
  SetState(dsIdle);
end;

class procedure TDebuggerIntf.SetProperties(const AProperties: TDebuggerProperties);
var
  Props: TDebuggerProperties;
begin
  if AProperties = nil then Exit;
  Props := GetProperties;
  if Props = AProperties then Exit;

  if Props = nil then Exit; // they weren't created ?
  Props.Assign(AProperties);
end;

class function TDebuggerIntf.RequiresLocalExecutable: Boolean;
begin
  Result := True;
end;

procedure TDebuggerIntf.SetState(const AValue: TDBGState);
var
  OldState: TDBGState;
begin
  // dsDestroying is final, do not unset
  if FState = dsDestroying
  then exit;

  // dsDestroying must be silent. The ide believes the debugger is gone already
  if AValue = dsDestroying
  then begin
    FState := AValue;
    exit;
  end;

  if AValue <> FState
  then begin
    DebugLnEnter(DBG_STATE, ['DebuggerState: Setting to ', dbgs(AValue),', from ', dbgs(FState)]);
    OldState := FState;
    FState := AValue;
    LockCommandProcessing;
    try
      DoBeforeState(OldState);
      try
        FThreads.DoStateChange(OldState);
        FCallStack.DoStateChange(OldState);
        FBreakpoints.DoStateChange(OldState);
        FLocals.DoStateChange(OldState);
        FLineInfo.DoStateChange(OldState);
        FRegisters.DoStateChange(OldState);
        FDisassembler.DoStateChange(OldState);
        FWatches.DoStateChange(OldState);
      finally
        DoState(OldState);
      end;
    finally
      UnLockCommandProcessing;
      DebugLnExit(DBG_STATE, ['DebuggerState: Finished ', dbgs(AValue)]);
    end;
  end;
end;

procedure TDebuggerIntf.SetErrorState(const AMsg: String; const AInfo: String = '');
begin
  if FErrorStateMessage = ''
  then FErrorStateMessage := AMsg;
  if FErrorStateInfo = ''
  then FErrorStateInfo := AInfo;
  SetState(dsError);
end;

procedure TDebuggerIntf.DoRelease;
begin
  Self.Free;
end;

procedure TDebuggerIntf.StepInto;
begin
  if ReqCmd(dcStepInto, []) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.StepInto Class=',ClassName,' failed.');
end;

procedure TDebuggerIntf.StepOverInstr;
begin
  if ReqCmd(dcStepOverInstr, []) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.StepOverInstr Class=',ClassName,' failed.');
end;

procedure TDebuggerIntf.StepIntoInstr;
begin
  if ReqCmd(dcStepIntoInstr, []) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.StepIntoInstr Class=',ClassName,' failed.');
end;

procedure TDebuggerIntf.StepOut;
begin
  if ReqCmd(dcStepOut, []) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.StepOut Class=', ClassName, ' failed.');
end;

procedure TDebuggerIntf.StepOver;
begin
  if ReqCmd(dcStepOver, []) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.StepOver Class=',ClassName,' failed.');
end;

procedure TDebuggerIntf.Stop;
begin
  if ReqCmd(dcStop,[]) then exit;
  DebugLn(DBG_WARNINGS, 'TDebuggerIntf.Stop Class=',ClassName,' failed.');
end;

function TBaseDebugManagerIntf.DebuggerCount: Integer;
begin
  Result := MDebuggerClasses.Count;
end;

function TBaseDebugManagerIntf.FindDebuggerClass(const AString: String): TDebuggerClass;
var
  idx: Integer;
begin
  idx := MDebuggerClasses.IndexOf(AString);
  if idx = -1
  then Result := nil
  else Result := TDebuggerClass(MDebuggerClasses.Objects[idx]);
end;

function TBaseDebugManagerIntf.GetDebuggerClass(const AIndex: Integer): TDebuggerClass;
begin
  Result := TDebuggerClass(MDebuggerClasses.Objects[AIndex]);
end;


initialization
  MDebuggerPropertiesList := nil;
  {$IFDEF DBG_STATE}  {$DEFINE DBG_STATE_EVENT} {$ENDIF}
  {$IFDEF DBG_EVENTS} {$DEFINE DBG_STATE_EVENT} {$ENDIF}
  DBG_VERBOSE := DebugLogger.FindOrRegisterLogGroup('DBG_VERBOSE' {$IFDEF DBG_VERBOSE} , True {$ENDIF} );
  DBG_WARNINGS := DebugLogger.FindOrRegisterLogGroup('DBG_WARNINGS' {$IFDEF DBG_WARNINGS} , True {$ENDIF} );
  DBG_STATE       := DebugLogger.FindOrRegisterLogGroup('DBG_STATE' {$IFDEF DBG_STATE} , True {$ENDIF} );
  DBG_EVENTS      := DebugLogger.FindOrRegisterLogGroup('DBG_EVENTS' {$IFDEF DBG_EVENTS} , True {$ENDIF} );
  DBG_STATE_EVENT := DebugLogger.FindOrRegisterLogGroup('DBG_STATE_EVENT' {$IFDEF DBG_STATE_EVENT} , True {$ENDIF} );
  DBG_DATA_MONITORS := DebugLogger.FindOrRegisterLogGroup('DBG_DATA_MONITORS' {$IFDEF DBG_DATA_MONITORS} , True {$ENDIF} );
  DBG_DISASSEMBLER := DebugLogger.FindOrRegisterLogGroup('DBG_DISASSEMBLER' {$IFDEF DBG_DISASSEMBLER} , True {$ENDIF} );

  MDebuggerClasses := TStringList.Create;
  MDebuggerClasses.Sorted := True;
  MDebuggerClasses.Duplicates := dupError;

finalization
  DoFinalization;
  FreeAndNil(MDebuggerClasses);

end.
