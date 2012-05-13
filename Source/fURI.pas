unit fURI;

interface {********************************************************************}

uses
  WinInet,
  SysUtils;

type
  TUURI = class
  private
    FDatabase: string;
    FParams: string;
    FPath: TFileName;
    FScheme: string;
    FTable: string;
    function GetAddress(): string;
    function GetParam(AName: string): Variant;
    function GetParamCount(): Integer;
    procedure SetAddress(const AAddress: string);
    procedure SetDatabase(const ADatabase: string);
    procedure SetParam(AName: string; const Value: Variant);
    procedure SetPath(const APath: TFileName);
    procedure SetScheme(const AScheme: string);
    procedure SetTable(const ATable: string);
  public
    Host: string;
    Username: string;
    Password: string;
    Port: INTERNET_PORT;
    property Address: string read GetAddress write SetAddress;
    property Database: string read FDatabase write SetDatabase;
    property Param[Name: string]: Variant read GetParam write SetParam;
    property ParamCount: Integer read GetParamCount;
    property Path: TFileName read FPath write SetPath;
    property Scheme: string read FScheme write SetScheme;
    property Table: string read FTable write SetTable;
    procedure Clear(); virtual;
    constructor Create(const AAddress: string = ''); virtual;
    function ParamDecode(const AParam: string): string;
    function ParamEncode(const AParam: string): string;
  end;

function PathToURI(const APath: TFileName): string;
function URIToPath(const AURI: string): TFileName;
function ExtractURIHost(const AURI: string): string;

implementation {***************************************************************}

uses
  RTLConsts, Variants, ShLwApi, Windows, Classes, StrUtils,
  MySQLConsts;

//  Used parameters:
//  Param['system']
//  Param['view']
//  Param['procedure']
//  Param['function']
//  Param['trigger']
//  Param['event']
//  Param['filter']
//  Param['offset']
//  Param['file']

function PathToURI(const APath: TFileName): string;
var
  Size: DWord;
  URL: Pointer;
begin
  URL := nil;

  try
    Size := (INTERNET_MAX_URL_LENGTH + 1) * SizeOf(Char);
    GetMem(URL, Size);
    if (UrlCreateFromPath(PChar(APath), URL, @Size, 0) <> S_OK) then
      raise EConvertError.CreateFmt(SConvStrParseError, [APath]);

    Result := PChar(URL);
  finally
    FreeMem(URL);
  end;
end;

function URIToPath(const AURI: string): TFileName;
var
  PathP: Pointer;
  Size: DWord;
begin
  PathP := nil;

  try
    Size := 2 * Length(AURI) + 1;
    GetMem(PathP, Size);
    if (PathCreateFromUrl(PChar(AURI), PathP, @Size, 0) <> S_OK) then
      raise EConvertError.CreateFmt(SConvStrParseError, [AURI]);

    Result := PChar(PathP);
  finally
    FreeMem(PathP);
  end;
end;

function ExtractURIHost(const AURI: string): string;
var
  URI: TUURI;
begin
  URI := TUURI.Create(AURI);

  Result := URI.Host;

  URI.Free();
end;

{ TUURI ***********************************************************************}

procedure TUURI.Clear();
begin
  Scheme := 'mysql';
  Username := '';
  Password := '';
  Host := '';
  Port := 0;
  FPath := '/';
  FParams := '';
end;

constructor TUURI.Create(const AAddress: string = '');
begin
  inherited Create();

  Address := AAddress;
end;

function TUURI.GetAddress(): string;
var
  Buffer: array [0 .. INTERNET_MAX_URL_LENGTH] of Char;
  Size: Cardinal;
  URLComponents: URL_COMPONENTS;
begin
  ZeroMemory(@URLComponents, SizeOf(URLComponents));
  URLComponents.dwStructSize := SizeOf(URLComponents);

  URLComponents.lpszScheme := PChar(Scheme);
  URLComponents.dwSchemeLength := StrLen(URLComponents.lpszScheme);
  URLComponents.lpszHostName := PChar(Host);
  URLComponents.dwHostNameLength := StrLen(URLComponents.lpszHostName);
  if (Port <> MYSQL_PORT) then
    URLComponents.nPort := Port;
  if (Username <> '') then
  begin
    URLComponents.lpszUserName := PChar(ParamEncode(Username));
    URLComponents.dwUserNameLength := StrLen(URLComponents.lpszUserName);
    if (Password <> '') then
    begin
      URLComponents.lpszPassword := PChar(ParamEncode(Password));
      URLComponents.dwPasswordLength := StrLen(URLComponents.lpszPassword);
    end;
  end;
  URLComponents.lpszUrlPath := PChar(ParamEncode(Path));
  URLComponents.dwUrlPathLength := StrLen(URLComponents.lpszUrlPath);
  URLComponents.lpszExtraInfo := PChar(Copy(FParams, 1, 1) + ParamEncode(Copy(FParams, 2, Length(FParams) - 1)));
  URLComponents.dwExtraInfoLength := StrLen(URLComponents.lpszExtraInfo);

  Size := SizeOf(Buffer);
  if (not InternetCreateUrl(URLComponents, 0, @Buffer, Size)) then
    Result := ''
  else
    SetString(Result, PChar(@Buffer), Size);
end;

function TUURI.GetParam(AName: string): Variant;
var
  I: Integer;
  Items: TStringList;
begin
  if (Length(FParams) <= 1) then
    Result := Null
  else
  begin
    Items := TStringList.Create();
    Items.Text := ReplaceStr(Copy(FParams, 2, Length(FParams) - 1), '&', #13#10);

    Result := Items.Values[AName];

    if (Result = '') then
    begin
      Result := Null;
      for I := 0 to Items.Count - 1 do
        if (AName + '=' = Items[I]) then
          Result := '';
    end;

    Items.Free();
  end;
end;

function TUURI.GetParamCount(): Integer;
var
  Items: TStringList;
begin
  if (Length(FParams) < 1) then
    Result := 0
  else
  begin
    Items := TStringList.Create();
    Items.Text := ReplaceStr(Copy(FParams, 2, Length(FParams) - 1), '&', #13#10);

    Result := Items.Count;

    Items.Free();
  end;
end;

function TUURI.ParamDecode(const AParam: string): string;
var
  Size: DWord;
  UnescapedURL: PChar;
begin
  Size := Length(AParam) + 1;
  GetMem(UnescapedURL, Size * SizeOf(UnescapedURL[0]));

  try
    if (UrlUnescape(PChar(AParam), UnescapedURL, @Size, 0) <> S_OK) then
      raise EConvertError.CreateFmt(SConvStrParseError, [AParam]);

    Result := UnescapedURL;
  finally
    if (Assigned(UnescapedURL)) then
      FreeMem(UnescapedURL);
  end;
end;

function TUURI.ParamEncode(const AParam: string): string;
var
  EscapedURL: PChar;
  S: string;
  Size: DWord;
begin
  if (AParam = '') then
    Result := ''
  else
  begin
    S := ReplaceStr(AParam, '#', '%23');
    S := ReplaceStr(S, '.', '%2e');
    S := ReplaceStr(S, '?', '%3f');
    S := ReplaceStr(S, '@', '%40');

    Size := Length(AParam) * 10 + 1;
    GetMem(EscapedURL, Size * SizeOf(EscapedURL[0]));

    try
      if (UrlEscape(PChar(S), EscapedURL, @Size, 0) <> S_OK) then
        raise EConvertError.CreateFmt(SConvStrParseError, [AParam]);

      Result := EscapedURL;
    finally
      FreeMem(EscapedURL);
    end;
  end;
end;

procedure TUURI.SetAddress(const AAddress: string);
var
  URLComponents: TURLComponents;
begin
  Clear();

  if (AAddress <> '') then
  begin
    URLComponents.dwStructSize := SizeOf(URLComponents);

    URLComponents.dwSchemeLength := INTERNET_MAX_SCHEME_LENGTH;
    URLComponents.dwHostNameLength := INTERNET_MAX_HOST_NAME_LENGTH;
    URLComponents.dwUserNameLength := INTERNET_MAX_USER_NAME_LENGTH;
    URLComponents.dwPasswordLength := INTERNET_MAX_PASSWORD_LENGTH;
    URLComponents.dwUrlPathLength := INTERNET_MAX_PATH_LENGTH;
    URLComponents.dwExtraInfoLength := INTERNET_MAX_PATH_LENGTH;

    GetMem(URLComponents.lpszScheme,    URLComponents.dwSchemeLength    * SizeOf(URLComponents.lpszScheme[0]));
    GetMem(URLComponents.lpszHostName,  URLComponents.dwHostNameLength  * SizeOf(URLComponents.lpszHostName[0]));
    GetMem(URLComponents.lpszUserName,  URLComponents.dwUserNameLength  * SizeOf(URLComponents.lpszUserName[0]));
    GetMem(URLComponents.lpszPassword,  URLComponents.dwPasswordLength  * SizeOf(URLComponents.lpszPassword[0]));
    GetMem(URLComponents.lpszUrlPath,   URLComponents.dwUrlPathLength   * SizeOf(URLComponents.lpszUrlPath[0]));
    GetMem(URLComponents.lpszExtraInfo, URLComponents.dwExtraInfoLength * SizeOf(URLComponents.lpszExtraInfo[0]));

    try
      if (not InternetCrackUrl(PChar(AAddress), Length(AAddress), 0, URLComponents)) then
        raise EConvertError.CreateFmt(SConvStrParseError, [AAddress]);

      Scheme := URLComponents.lpszScheme;
      Username := ParamDecode(URLComponents.lpszUserName);
      Password := ParamDecode(URLComponents.lpszPassword);
      Host := URLComponents.lpszHostName;
      if (URLComponents.nPort = 0) then
        Port := MYSQL_PORT
      else
        Port := URLComponents.nPort;
      Path := ParamDecode(URLComponents.lpszUrlPath);
      if (URLComponents.dwExtraInfoLength = 0) then
        FParams := ''
      else
        FParams := Copy(URLComponents.lpszExtraInfo, 1, 1) + ParamDecode(Copy(URLComponents.lpszExtraInfo, 2, URLComponents.dwExtraInfoLength - 1));
    finally
      FreeMem(URLComponents.lpszScheme);
      FreeMem(URLComponents.lpszHostName);
      FreeMem(URLComponents.lpszUserName);
      FreeMem(URLComponents.lpszPassword);
      FreeMem(URLComponents.lpszUrlPath);
      FreeMem(URLComponents.lpszExtraInfo);
    end;
  end;
end;

procedure TUURI.SetDatabase(const ADatabase: string);
var
  S: string;
begin
  S := Path;
  if (Database <> '') and (Pos('/' + ParamEncode(Database), S) = 1) then
    Delete(S, 1, 1 + Length(ParamEncode(Database)));

  FDatabase := ADatabase;
  FTable := '';

  if (ADatabase <> '') then
    S := '/' + ParamEncode(ADatabase) + S;

  FPath := S;
end;

procedure TUURI.SetParam(AName: string; const Value: Variant);
var
  Items: TStringList;
begin
  Items := TStringList.Create();
  if (Length(FParams) > 1) then
    Items.Text := ReplaceStr(Copy(FParams, 2, Length(FParams) - 1), '&', #13#10);

  if (Value = Null) then
    Items.Values[AName] := ''
  else
    Items.Values[AName] := Value;

  FParams := ReplaceStr(Trim(Items.Text), #13#10, '&');

  if (FParams <> '') then
    FParams := '?' + FParams;

  Items.Free();
end;

procedure TUURI.SetPath(const APath: TFileName);
begin
  if (Pos('/', APath) <> 1) then
  begin
    FDatabase := '';
    FTable := '';
    FPath := '';
  end
  else
  begin
    FDatabase := Copy(APath, 2, Length(APath) - 1);
    if (copy(FDatabase, Length(FDatabase), 1) = '/') then
      Delete(FDatabase, Length(FDatabase), 1);
    if (Pos('/', FDatabase) > 0) then
    begin
      FTable := Copy(FDatabase, Pos('/', FDatabase) + 1, Length(FDatabase) - Pos('/', FDatabase));
      Delete(FDatabase, Pos('/', FDatabase), Length(FDatabase) - Pos('/', FDatabase) + 1);
    end;
    FDatabase := ParamDecode(FDatabase);
    FTable := ParamDecode(FTable);
    FPath := APath;
  end;
end;

procedure TUURI.SetScheme(const AScheme: string);
begin
  FScheme := LowerCase(AScheme);
end;

procedure TUURI.SetTable(const ATable: string);
begin
  FTable := ATable;

  FPath := '/';
  if (FTable <> '') then
    FPath := '/' + ParamEncode(FTable) + FPath;
  if (FDatabase <> '') then
    FPath := '/' + ParamEncode(FDatabase) + FPath;
end;

end.

