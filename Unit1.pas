unit Unit1;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Collections,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Grids,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.ComCtrls;

type
  // Запись квитанции о сданной в ремонт радиоаппаратуре.
  TOrder = record
    GroupName: string;
    Brand: string;
    AcceptDate: string;
    EmployeeCode: string;
    IsDone: Boolean;
  end;

  // Запись сотрудника радиоателье.
  TEmployee = record
    Code: string;
    FullName: string;
    Position: string;
    HoursPerDay: Integer;
  end;

  // Определяет, какая таблица сейчас отображается на форме.
  TCurrentTable = (ctOrders, ctEmployees);

  TForm1 = class(TForm)
    Label1: TLabel;
    gridMain: TStringGrid;
    btnSwitchTable: TButton;
    btnSearch: TButton;
    btnCancelSearch: TButton;
    btnReadyToday: TButton;
    btnEmployeeReport: TButton;
    btnAdd: TButton;
    edtSearch: TEdit;
    dtpFrom: TDateTimePicker;
    dtpTo: TDateTimePicker;
    MainMenu1: TMainMenu;
    mnuFile: TMenuItem;
    mnuLoad: TMenuItem;
    mnuSave: TMenuItem;
    mnuSaveAs: TMenuItem;
    mnuExitNoSave: TMenuItem;

    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    procedure btnSwitchTableClick(Sender: TObject);
    procedure btnSearchClick(Sender: TObject);
    procedure btnCancelSearchClick(Sender: TObject);
    procedure btnAddClick(Sender: TObject);
    procedure btnReadyTodayClick(Sender: TObject);
    procedure btnEmployeeReportClick(Sender: TObject);

    procedure mnuLoadClick(Sender: TObject);
    procedure mnuSaveClick(Sender: TObject);
    procedure mnuSaveAsClick(Sender: TObject);
    procedure mnuExitNoSaveClick(Sender: TObject);

    procedure gridMainDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure gridMainMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure gridMainSelectCell(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure gridMainSetEditText(Sender: TObject; ACol, ARow: Integer;
      const Value: string);
    procedure gridMainExit(Sender: TObject);

  private
    // Основные динамические списки данных программы.
    Orders: TList<TOrder>;
    Employees: TList<TEmployee>;

    // Списки индексов строк, отображаемых в таблице после фильтрации.
    ViewOrderIndexes: TList<Integer>;
    ViewEmployeeIndexes: TList<Integer>;

    CurrentTable: TCurrentTable;
    CurrentFileName: string;
    IsFiltered: Boolean;
    IsLoadingGrid: Boolean;
    IsModified: Boolean;
    ForceCloseWithoutSaving: Boolean;
    SaveWasCancelled: Boolean;

    procedure LoadDataFromFile(const FileName: string);
    procedure SaveDataToFile(const FileName: string);

    procedure ShowOrdersTable;
    procedure ShowEmployeesTable;
    procedure RefreshCurrentTable;
    procedure BuildFullViewIndexes;

    procedure SearchInCurrentTable(const SearchText: string);
    procedure CancelSearch;

    procedure AddRecordToCurrentTable;
    procedure DeleteRecordFromCurrentTable(VisibleRow: Integer);

    function CommitCurrentCell: Boolean;
    function CommitGridCell(ACol, ARow: Integer): Boolean;

    procedure SortCurrentTableByColumn(ACol: Integer);

    procedure ShowReadyTodayReport;
    procedure ShowEmployeeReport(DateFrom, DateTo: TDate);

    function GetEmployeeFullNameByCode(const Code: string): string;
    function SelectEmployeeCode: string;
    function SelectReadyStatus(var Ready: Boolean): Boolean;
    procedure UpdateEmployeeCodeInOrders(const OldCode, NewCode: string);

    function OrderContainsText(const Order: TOrder; const SearchText: string): Boolean;
    function EmployeeContainsText(const Employee: TEmployee; const SearchText: string): Boolean;

    function TryParseDateRu(const S: string; out D: TDate): Boolean;
    function IsSameRuDate(const S: string; D: TDate): Boolean;

    function BoolToReadyText(Value: Boolean): string;
    function ReadyTextToBool(const S: string; out Value: Boolean): Boolean;
    function BoolToFileText(Value: Boolean): string;

    function IsDigitsOnly(const S: string): Boolean;
    function EmployeeCodeExists(const Code: string; ExceptIndex: Integer): Boolean;
    function GenerateNextEmployeeCode: string;

    procedure SplitLine(const S: string; Parts: TStrings);
    function EscapeField(const S: string): string;
    function UnescapeField(const S: string): string;

    procedure PrepareGridBase;
    procedure CreateReportWindow(const Title, HeaderLine: string; DataRows: TStrings);

    function AskSaveChangesRussian: Integer;
    function AskDeleteRussian: Boolean;
  public
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

// Освобождение динамических списков при закрытии формы.
destructor TForm1.Destroy;
begin
  Orders.Free;
  Employees.Free;
  ViewOrderIndexes.Free;
  ViewEmployeeIndexes.Free;
  inherited;
end;

// Инициализация формы и начальных параметров программы.
procedure TForm1.FormCreate(Sender: TObject);
begin
  Orders := TList<TOrder>.Create;
  Employees := TList<TEmployee>.Create;
  ViewOrderIndexes := TList<Integer>.Create;
  ViewEmployeeIndexes := TList<Integer>.Create;

  CurrentTable := ctOrders;
  CurrentFileName := '';
  IsFiltered := False;
  IsLoadingGrid := False;
  IsModified := False;
  ForceCloseWithoutSaving := False;
  SaveWasCancelled := False;

  dtpFrom.Date := Date;
  dtpTo.Date := Date;

  PrepareGridBase;
  BuildFullViewIndexes;
  ShowOrdersTable;
end;

// Настройка основного табличного компонента.
procedure TForm1.PrepareGridBase;
begin
  gridMain.FixedRows := 1;
  gridMain.FixedCols := 0;
  gridMain.ScrollBars := ssVertical;

  gridMain.Options := gridMain.Options + [
    goEditing,
    goFixedVertLine,
    goFixedHorzLine,
    goVertLine,
    goHorzLine,
    goColSizing
  ];

  gridMain.Options := gridMain.Options - [goRowSelect];
end;

// Формирует полные списки индексов для отображения всех записей.
procedure TForm1.BuildFullViewIndexes;
var
  I: Integer;
begin
  ViewOrderIndexes.Clear;
  for I := 0 to Orders.Count - 1 do
    ViewOrderIndexes.Add(I);

  ViewEmployeeIndexes.Clear;
  for I := 0 to Employees.Count - 1 do
    ViewEmployeeIndexes.Add(I);
end;

// Обновляет таблицу с учетом текущей таблицы и режима фильтрации.
procedure TForm1.RefreshCurrentTable;
begin
  if IsFiltered then
    SearchInCurrentTable(edtSearch.Text)
  else
  begin
    BuildFullViewIndexes;

    if CurrentTable = ctOrders then
      ShowOrdersTable
    else
      ShowEmployeesTable;
  end;
end;

// Выводит список квитанций в TStringGrid.
procedure TForm1.ShowOrdersTable;
var
  I, SourceIndex: Integer;
  OrderItem: TOrder;
begin
  IsLoadingGrid := True;

  gridMain.FixedCols := 0;
  gridMain.ScrollBars := ssVertical;

  gridMain.ColCount := 6;
  gridMain.RowCount := ViewOrderIndexes.Count + 1;

  gridMain.Cells[0, 0] := 'Группа изделия';
  gridMain.Cells[1, 0] := 'Марка';
  gridMain.Cells[2, 0] := 'Дата приёмки';
  gridMain.Cells[3, 0] := 'Сотрудник';
  gridMain.Cells[4, 0] := 'Готовность';
  gridMain.Cells[5, 0] := 'Удалить';

  gridMain.ColWidths[0] := 125;
  gridMain.ColWidths[1] := 105;
  gridMain.ColWidths[2] := 95;
  gridMain.ColWidths[3] := 160;
  gridMain.ColWidths[4] := 90;
  gridMain.ColWidths[5] := 70;

  for I := 0 to ViewOrderIndexes.Count - 1 do
  begin
    SourceIndex := ViewOrderIndexes[I];
    OrderItem := Orders[SourceIndex];

    gridMain.Cells[0, I + 1] := OrderItem.GroupName;
    gridMain.Cells[1, I + 1] := OrderItem.Brand;
    gridMain.Cells[2, I + 1] := OrderItem.AcceptDate;
    gridMain.Cells[3, I + 1] := GetEmployeeFullNameByCode(OrderItem.EmployeeCode);
    gridMain.Cells[4, I + 1] := BoolToReadyText(OrderItem.IsDone);
    gridMain.Cells[5, I + 1] := 'Удалить';
  end;

  btnSwitchTable.Caption := 'Сотрудники';

  IsLoadingGrid := False;
end;

// Выводит список сотрудников в TStringGrid.
procedure TForm1.ShowEmployeesTable;
var
  I, SourceIndex: Integer;
  EmployeeItem: TEmployee;
begin
  IsLoadingGrid := True;

  gridMain.FixedCols := 0;
  gridMain.ScrollBars := ssVertical;

  gridMain.ColCount := 5;
  gridMain.RowCount := ViewEmployeeIndexes.Count + 1;

  gridMain.Cells[0, 0] := 'Код';
  gridMain.Cells[1, 0] := 'ФИО';
  gridMain.Cells[2, 0] := 'Должность';
  gridMain.Cells[3, 0] := 'Часов в сутки';
  gridMain.Cells[4, 0] := 'Удалить';

  gridMain.ColWidths[0] := 75;
  gridMain.ColWidths[1] := 220;
  gridMain.ColWidths[2] := 140;
  gridMain.ColWidths[3] := 95;
  gridMain.ColWidths[4] := 70;

  for I := 0 to ViewEmployeeIndexes.Count - 1 do
  begin
    SourceIndex := ViewEmployeeIndexes[I];
    EmployeeItem := Employees[SourceIndex];

    gridMain.Cells[0, I + 1] := EmployeeItem.Code;
    gridMain.Cells[1, I + 1] := EmployeeItem.FullName;
    gridMain.Cells[2, I + 1] := EmployeeItem.Position;
    gridMain.Cells[3, I + 1] := IntToStr(EmployeeItem.HoursPerDay);
    gridMain.Cells[4, I + 1] := 'Удалить';
  end;

  btnSwitchTable.Caption := 'Квитанции';

  IsLoadingGrid := False;
end;

procedure TForm1.btnSwitchTableClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  if CurrentTable = ctOrders then
    CurrentTable := ctEmployees
  else
    CurrentTable := ctOrders;

  edtSearch.Text := '';
  CancelSearch;
end;

procedure TForm1.btnSearchClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  SearchInCurrentTable(edtSearch.Text);
end;

procedure TForm1.btnCancelSearchClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  edtSearch.Text := '';
  CancelSearch;
end;

procedure TForm1.btnAddClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  AddRecordToCurrentTable;
end;

procedure TForm1.btnReadyTodayClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  ShowReadyTodayReport;
end;

procedure TForm1.btnEmployeeReportClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  ShowEmployeeReport(dtpFrom.Date, dtpTo.Date);
end;

// Загрузка данных из dat-файла с текстовой структурой строк.
procedure TForm1.mnuLoadClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Filter := 'Файлы данных (*.dat)|*.dat|Все файлы (*.*)|*.*';
    Dlg.DefaultExt := 'dat';

    if Dlg.Execute then
    begin
      LoadDataFromFile(Dlg.FileName);
      CurrentFileName := Dlg.FileName;
      IsModified := False;
      edtSearch.Text := '';
      CancelSearch;
      ShowMessage('Файл загружен.');
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.mnuSaveClick(Sender: TObject);
begin
  if not CommitCurrentCell then
    Exit;

  SaveWasCancelled := False;

  if CurrentFileName = '' then
    mnuSaveAsClick(Sender)
  else
  begin
    SaveDataToFile(CurrentFileName);
    IsModified := False;
    ShowMessage('Файл сохранён.');
  end;
end;

procedure TForm1.mnuSaveAsClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  if not CommitCurrentCell then
    Exit;

  SaveWasCancelled := False;

  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := 'Файлы данных (*.dat)|*.dat|Все файлы (*.*)|*.*';
    Dlg.DefaultExt := 'dat';

    if Dlg.Execute then
    begin
      SaveDataToFile(Dlg.FileName);
      CurrentFileName := Dlg.FileName;
      IsModified := False;
      ShowMessage('Файл сохранён.');
    end
    else
      SaveWasCancelled := True;
  finally
    Dlg.Free;
  end;
end;

procedure TForm1.mnuExitNoSaveClick(Sender: TObject);
begin
  ForceCloseWithoutSaving := True;
  Close;
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Answer: Integer;
begin
  if ForceCloseWithoutSaving then
  begin
    CanClose := True;
    Exit;
  end;

  if not CommitCurrentCell then
  begin
    CanClose := False;
    Exit;
  end;

  if not IsModified then
  begin
    CanClose := True;
    Exit;
  end;

  Answer := AskSaveChangesRussian;

  case Answer of
    mrYes:
      begin
        mnuSaveClick(Sender);

        if SaveWasCancelled then
          CanClose := False
        else
          CanClose := True;
      end;

    mrNo:
      CanClose := True;

    mrCancel:
      CanClose := False;
  end;
end;

// Диалог выхода с русскими кнопками.
function TForm1.AskSaveChangesRussian: Integer;
var
  F: TForm;
  L: TLabel;
  BtnSave, BtnNoSave, BtnCancel: TButton;
begin
  Result := mrCancel;

  F := TForm.Create(nil);
  try
    F.Caption := 'Подтверждение выхода';
    F.Width := 390;
    F.Height := 155;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Left := 20;
    L.Top := 20;
    L.Width := 340;
    L.Caption := 'Сохранить изменения перед выходом?';

    BtnSave := TButton.Create(F);
    BtnSave.Parent := F;
    BtnSave.Left := 20;
    BtnSave.Top := 70;
    BtnSave.Width := 105;
    BtnSave.Caption := 'Сохранить';
    BtnSave.ModalResult := mrYes;

    BtnNoSave := TButton.Create(F);
    BtnNoSave.Parent := F;
    BtnNoSave.Left := 135;
    BtnNoSave.Top := 70;
    BtnNoSave.Width := 115;
    BtnNoSave.Caption := 'Не сохранять';
    BtnNoSave.ModalResult := mrNo;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 260;
    BtnCancel.Top := 70;
    BtnCancel.Width := 95;
    BtnCancel.Caption := 'Отмена';
    BtnCancel.ModalResult := mrCancel;

    Result := F.ShowModal;
  finally
    F.Free;
  end;
end;

// Диалог подтверждения удаления записи.
function TForm1.AskDeleteRussian: Boolean;
var
  F: TForm;
  L: TLabel;
  BtnYes, BtnNo: TButton;
begin
  Result := False;

  F := TForm.Create(nil);
  try
    F.Caption := 'Удаление записи';
    F.Width := 330;
    F.Height := 145;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Left := 20;
    L.Top := 20;
    L.Width := 280;
    L.Caption := 'Удалить выбранную запись?';

    BtnYes := TButton.Create(F);
    BtnYes.Parent := F;
    BtnYes.Left := 60;
    BtnYes.Top := 65;
    BtnYes.Width := 90;
    BtnYes.Caption := 'Да';
    BtnYes.ModalResult := mrYes;

    BtnNo := TButton.Create(F);
    BtnNo.Parent := F;
    BtnNo.Left := 170;
    BtnNo.Top := 65;
    BtnNo.Width := 90;
    BtnNo.Caption := 'Нет';
    BtnNo.ModalResult := mrNo;

    Result := F.ShowModal = mrYes;
  finally
    F.Free;
  end;
end;

// Чтение dat-файла. Внутренний формат строк остается текстовым.
procedure TForm1.LoadDataFromFile(const FileName: string);
var
  Lines: TStringList;
  Parts: TStringList;
  I: Integer;
  Section: string;
  OrderItem: TOrder;
  EmployeeItem: TEmployee;
begin
  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Lines.LoadFromFile(FileName, TEncoding.UTF8);

    Orders.Clear;
    Employees.Clear;

    Section := '';

    for I := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;

      if SameText(Trim(Lines[I]), '[ORDERS]') then
      begin
        Section := 'ORDERS';
        Continue;
      end;

      if SameText(Trim(Lines[I]), '[EMPLOYEES]') then
      begin
        Section := 'EMPLOYEES';
        Continue;
      end;

      SplitLine(Lines[I], Parts);

      if SameText(Section, 'ORDERS') then
      begin
        if Parts.Count >= 5 then
        begin
          OrderItem.GroupName := UnescapeField(Parts[0]);
          OrderItem.Brand := UnescapeField(Parts[1]);
          OrderItem.AcceptDate := UnescapeField(Parts[2]);
          OrderItem.EmployeeCode := UnescapeField(Parts[3]);
          OrderItem.IsDone := Parts[4] = '1';

          Orders.Add(OrderItem);
        end;
      end
      else if SameText(Section, 'EMPLOYEES') then
      begin
        if Parts.Count >= 4 then
        begin
          EmployeeItem.Code := UnescapeField(Parts[0]);
          EmployeeItem.FullName := UnescapeField(Parts[1]);
          EmployeeItem.Position := UnescapeField(Parts[2]);
          EmployeeItem.HoursPerDay := StrToIntDef(Parts[3], 0);

          Employees.Add(EmployeeItem);
        end;
      end;
    end;

    BuildFullViewIndexes;
  finally
    Lines.Free;
    Parts.Free;
  end;
end;

// Сохранение данных в dat-файл с тем же текстовым содержимым.
procedure TForm1.SaveDataToFile(const FileName: string);
var
  Lines: TStringList;
  I: Integer;
  OrderItem: TOrder;
  EmployeeItem: TEmployee;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('[ORDERS]');

    for I := 0 to Orders.Count - 1 do
    begin
      OrderItem := Orders[I];

      Lines.Add(
        EscapeField(OrderItem.GroupName) + ';' +
        EscapeField(OrderItem.Brand) + ';' +
        EscapeField(OrderItem.AcceptDate) + ';' +
        EscapeField(OrderItem.EmployeeCode) + ';' +
        BoolToFileText(OrderItem.IsDone)
      );
    end;

    Lines.Add('');
    Lines.Add('[EMPLOYEES]');

    for I := 0 to Employees.Count - 1 do
    begin
      EmployeeItem := Employees[I];

      Lines.Add(
        EscapeField(EmployeeItem.Code) + ';' +
        EscapeField(EmployeeItem.FullName) + ';' +
        EscapeField(EmployeeItem.Position) + ';' +
        IntToStr(EmployeeItem.HoursPerDay)
      );
    end;

    Lines.SaveToFile(FileName, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

// Фильтрация текущего списка по подстроке.
procedure TForm1.SearchInCurrentTable(const SearchText: string);
var
  I: Integer;
  S: string;
begin
  S := AnsiLowerCase(Trim(SearchText));
  IsFiltered := S <> '';

  if S = '' then
  begin
    CancelSearch;
    Exit;
  end;

  if CurrentTable = ctOrders then
  begin
    ViewOrderIndexes.Clear;

    for I := 0 to Orders.Count - 1 do
      if OrderContainsText(Orders[I], S) then
        ViewOrderIndexes.Add(I);

    ShowOrdersTable;
  end
  else
  begin
    ViewEmployeeIndexes.Clear;

    for I := 0 to Employees.Count - 1 do
      if EmployeeContainsText(Employees[I], S) then
        ViewEmployeeIndexes.Add(I);

    ShowEmployeesTable;
  end;
end;

procedure TForm1.CancelSearch;
begin
  IsFiltered := False;
  BuildFullViewIndexes;

  if CurrentTable = ctOrders then
    ShowOrdersTable
  else
    ShowEmployeesTable;
end;

// Добавление новой записи в активный динамический список.
procedure TForm1.AddRecordToCurrentTable;
var
  OrderItem: TOrder;
  EmployeeItem: TEmployee;
begin
  if CurrentTable = ctOrders then
  begin
    OrderItem.GroupName := '';
    OrderItem.Brand := '';
    OrderItem.AcceptDate := FormatDateTime('dd.mm.yyyy', Date);
    OrderItem.EmployeeCode := '';
    OrderItem.IsDone := False;

    Orders.Add(OrderItem);
  end
  else
  begin
    EmployeeItem.Code := GenerateNextEmployeeCode;
    EmployeeItem.FullName := '';
    EmployeeItem.Position := '';
    EmployeeItem.HoursPerDay := 0;

    Employees.Add(EmployeeItem);
  end;

  IsModified := True;
  CancelSearch;
end;

// Удаление записи из активного динамического списка.
procedure TForm1.DeleteRecordFromCurrentTable(VisibleRow: Integer);
var
  SourceIndex: Integer;
begin
  if VisibleRow <= 0 then
    Exit;

  if not AskDeleteRussian then
    Exit;

  if CurrentTable = ctOrders then
  begin
    if VisibleRow - 1 >= ViewOrderIndexes.Count then
      Exit;

    SourceIndex := ViewOrderIndexes[VisibleRow - 1];
    Orders.Delete(SourceIndex);
  end
  else
  begin
    if VisibleRow - 1 >= ViewEmployeeIndexes.Count then
      Exit;

    SourceIndex := ViewEmployeeIndexes[VisibleRow - 1];
    Employees.Delete(SourceIndex);
  end;

  IsModified := True;
  RefreshCurrentTable;
end;

function TForm1.CommitCurrentCell: Boolean;
begin
  Result := CommitGridCell(gridMain.Col, gridMain.Row);
end;

// Проверка и сохранение значения из редактируемой ячейки.
function TForm1.CommitGridCell(ACol, ARow: Integer): Boolean;
var
  SourceIndex: Integer;
  Value: string;
  OldCode: string;
  ParsedDate: TDate;
  Hours: Integer;
  ReadyValue: Boolean;
  OrderItem: TOrder;
  EmployeeItem: TEmployee;
begin
  Result := True;

  if IsLoadingGrid then
    Exit;

  if ARow <= 0 then
    Exit;

  Value := Trim(gridMain.Cells[ACol, ARow]);

  if CurrentTable = ctOrders then
  begin
    if ARow - 1 >= ViewOrderIndexes.Count then
      Exit;

    SourceIndex := ViewOrderIndexes[ARow - 1];
    OrderItem := Orders[SourceIndex];

    case ACol of
      0:
        OrderItem.GroupName := Value;

      1:
        OrderItem.Brand := Value;

      2:
        begin
          if not TryParseDateRu(Value, ParsedDate) then
          begin
            ShowMessage('Дата приёмки должна быть настоящей датой в формате дд.мм.гггг.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          OrderItem.AcceptDate := FormatDateTime('dd.mm.yyyy', ParsedDate);
        end;

      4:
        begin
          if not ReadyTextToBool(Value, ReadyValue) then
          begin
            ShowMessage('Готовность может быть только "Выполнен" или "Не выполнен".');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          OrderItem.IsDone := ReadyValue;
        end;
    end;

    Orders[SourceIndex] := OrderItem;
  end
  else
  begin
    if ARow - 1 >= ViewEmployeeIndexes.Count then
      Exit;

    SourceIndex := ViewEmployeeIndexes[ARow - 1];
    EmployeeItem := Employees[SourceIndex];

    case ACol of
      0:
        begin
          if Value = '' then
          begin
            ShowMessage('Код сотрудника не может быть пустым.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          if not IsDigitsOnly(Value) then
          begin
            ShowMessage('Код сотрудника может состоять только из цифр.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          if EmployeeCodeExists(Value, SourceIndex) then
          begin
            ShowMessage('Сотрудник с таким кодом уже существует.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          OldCode := EmployeeItem.Code;
          EmployeeItem.Code := Value;
          Employees[SourceIndex] := EmployeeItem;
          UpdateEmployeeCodeInOrders(OldCode, Value);
        end;

      1:
        EmployeeItem.FullName := Value;

      2:
        EmployeeItem.Position := Value;

      3:
        begin
          if Value = '' then
          begin
            ShowMessage('Количество рабочих часов не может быть пустым.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          if not IsDigitsOnly(Value) then
          begin
            ShowMessage('Количество рабочих часов должно быть числом.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          Hours := StrToIntDef(Value, -1);

          if (Hours < 0) or (Hours > 24) then
          begin
            ShowMessage('Количество рабочих часов должно быть в пределах от 0 до 24.');
            RefreshCurrentTable;
            Result := False;
            Exit;
          end;

          EmployeeItem.HoursPerDay := Hours;
        end;
    end;

    Employees[SourceIndex] := EmployeeItem;
  end;

  IsModified := True;
  RefreshCurrentTable;
end;

procedure TForm1.gridMainMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  ACol, ARow: Integer;
  SourceIndex: Integer;
  NewCode: string;
  NewReady: Boolean;
  OrderItem: TOrder;
begin
  gridMain.MouseToCell(X, Y, ACol, ARow);

  if ARow = 0 then
  begin
    if not CommitCurrentCell then
      Exit;

    SortCurrentTableByColumn(ACol);
    Exit;
  end;

  if ARow <= 0 then
    Exit;

  if CurrentTable = ctOrders then
  begin
    if ACol = 5 then
    begin
      if not CommitCurrentCell then
        Exit;

      DeleteRecordFromCurrentTable(ARow);
      Exit;
    end;

    if ACol = 3 then
    begin
      if not CommitCurrentCell then
        Exit;

      if ARow - 1 >= ViewOrderIndexes.Count then
        Exit;

      SourceIndex := ViewOrderIndexes[ARow - 1];
      OrderItem := Orders[SourceIndex];

      NewCode := SelectEmployeeCode;

      if NewCode <> '' then
      begin
        OrderItem.EmployeeCode := NewCode;
        Orders[SourceIndex] := OrderItem;
        IsModified := True;
        RefreshCurrentTable;
      end;

      Exit;
    end;

    if ACol = 4 then
    begin
      if not CommitCurrentCell then
        Exit;

      if ARow - 1 >= ViewOrderIndexes.Count then
        Exit;

      SourceIndex := ViewOrderIndexes[ARow - 1];
      OrderItem := Orders[SourceIndex];
      NewReady := OrderItem.IsDone;

      if SelectReadyStatus(NewReady) then
      begin
        OrderItem.IsDone := NewReady;
        Orders[SourceIndex] := OrderItem;
        IsModified := True;
        RefreshCurrentTable;
      end;

      Exit;
    end;
  end
  else
  begin
    if ACol = 4 then
    begin
      if not CommitCurrentCell then
        Exit;

      DeleteRecordFromCurrentTable(ARow);
      Exit;
    end;
  end;
end;

procedure TForm1.gridMainSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  CanSelect := True;

  if not IsLoadingGrid then
  begin
    if (gridMain.Row > 0) and
       ((gridMain.Col <> ACol) or (gridMain.Row <> ARow)) then
    begin
      if not CommitGridCell(gridMain.Col, gridMain.Row) then
      begin
        CanSelect := False;
        Exit;
      end;
    end;
  end;

  if ARow = 0 then
  begin
    gridMain.Options := gridMain.Options - [goEditing];
    Exit;
  end;

  if CurrentTable = ctOrders then
  begin
    if (ACol = 3) or (ACol = 4) or (ACol = 5) then
      gridMain.Options := gridMain.Options - [goEditing]
    else
      gridMain.Options := gridMain.Options + [goEditing];
  end
  else
  begin
    if ACol = 4 then
      gridMain.Options := gridMain.Options - [goEditing]
    else
      gridMain.Options := gridMain.Options + [goEditing];
  end;
end;

procedure TForm1.gridMainSetEditText(Sender: TObject; ACol, ARow: Integer;
  const Value: string);
begin
  if IsLoadingGrid then
    Exit;

  IsModified := True;
end;

procedure TForm1.gridMainExit(Sender: TObject);
begin
  CommitCurrentCell;
end;

// Сортировка активного динамического списка по выбранному столбцу.
procedure TForm1.SortCurrentTableByColumn(ACol: Integer);
var
  I, J: Integer;

  function CompareDates(const A, B: string): Integer;
  var
    DateA, DateB: TDate;
    HasDateA, HasDateB: Boolean;
  begin
    HasDateA := TryParseDateRu(A, DateA);
    HasDateB := TryParseDateRu(B, DateB);

    if HasDateA and HasDateB then
    begin
      if DateA < DateB then
        Result := -1
      else if DateA > DateB then
        Result := 1
      else
        Result := 0;
    end
    else
      Result := CompareText(A, B);
  end;

  function CompareOrders(const A, B: TOrder): Integer;
  begin
    Result := 0;

    case ACol of
      0: Result := CompareText(A.GroupName, B.GroupName);
      1: Result := CompareText(A.Brand, B.Brand);
      2: Result := CompareDates(A.AcceptDate, B.AcceptDate);
      3: Result := CompareText(GetEmployeeFullNameByCode(A.EmployeeCode),
                               GetEmployeeFullNameByCode(B.EmployeeCode));
      4: Result := CompareText(BoolToReadyText(A.IsDone), BoolToReadyText(B.IsDone));
    end;
  end;

  function CompareEmployees(const A, B: TEmployee): Integer;
  begin
    Result := 0;

    case ACol of
      0: Result := CompareText(A.Code, B.Code);
      1: Result := CompareText(A.FullName, B.FullName);
      2: Result := CompareText(A.Position, B.Position);
      3: Result := A.HoursPerDay - B.HoursPerDay;
    end;
  end;

begin
  if CurrentTable = ctOrders then
  begin
    if ACol = 5 then
      Exit;

    for I := 0 to Orders.Count - 2 do
      for J := I + 1 to Orders.Count - 1 do
        if CompareOrders(Orders[I], Orders[J]) > 0 then
          Orders.Exchange(I, J);
  end
  else
  begin
    if ACol = 4 then
      Exit;

    for I := 0 to Employees.Count - 2 do
      for J := I + 1 to Employees.Count - 1 do
        if CompareEmployees(Employees[I], Employees[J]) > 0 then
          Employees.Exchange(I, J);
  end;

  IsModified := True;
  RefreshCurrentTable;
end;

// Отрисовка ячеек и псевдокнопок удаления.
procedure TForm1.gridMainDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
var
  Text: string;
  R: TRect;
begin
  Text := gridMain.Cells[ACol, ARow];

  if ARow = 0 then
  begin
    gridMain.Canvas.Brush.Color := clBtnFace;
    gridMain.Canvas.Font.Color := clBlack;
    gridMain.Canvas.Font.Style := [fsBold];
  end
  else
  begin
    gridMain.Canvas.Brush.Color := clWhite;
    gridMain.Canvas.Font.Color := clBlack;
    gridMain.Canvas.Font.Style := [];
  end;

  if gdSelected in State then
    gridMain.Canvas.Brush.Color := clSkyBlue;

  gridMain.Canvas.FillRect(Rect);

  if ((CurrentTable = ctOrders) and (ACol = 5) and (ARow > 0)) or
     ((CurrentTable = ctEmployees) and (ACol = 4) and (ARow > 0)) then
  begin
    R := Rect;
    InflateRect(R, -4, -4);

    DrawFrameControl(gridMain.Canvas.Handle, R, DFC_BUTTON, DFCS_BUTTONPUSH);

    DrawText(gridMain.Canvas.Handle, PChar(Text), Length(Text), R,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  end
  else
  begin
    R := Rect;
    InflateRect(R, -4, -2);

    DrawText(gridMain.Canvas.Handle, PChar(Text), Length(Text), R,
      DT_LEFT or DT_VCENTER or DT_SINGLELINE);
  end;
end;

// Окно выбора сотрудника для квитанции.
function TForm1.SelectEmployeeCode: string;
var
  F: TForm;
  G: TStringGrid;
  BtnOk, BtnCancel: TButton;
  I: Integer;
  EmployeeItem: TEmployee;
begin
  Result := '';

  F := TForm.Create(nil);
  try
    F.Caption := 'Выбор сотрудника';
    F.Width := 430;
    F.Height := 320;
    F.Position := poScreenCenter;

    G := TStringGrid.Create(F);
    G.Parent := F;
    G.Align := alTop;
    G.Height := 230;
    G.FixedRows := 1;
    G.FixedCols := 0;
    G.ScrollBars := ssVertical;
    G.ColCount := 2;
    G.RowCount := Employees.Count + 1;
    G.Options := G.Options + [goRowSelect];
    G.Cells[0, 0] := 'Код';
    G.Cells[1, 0] := 'ФИО';
    G.ColWidths[0] := 100;
    G.ColWidths[1] := 280;

    for I := 0 to Employees.Count - 1 do
    begin
      EmployeeItem := Employees[I];
      G.Cells[0, I + 1] := EmployeeItem.Code;
      G.Cells[1, I + 1] := EmployeeItem.FullName;
    end;

    BtnOk := TButton.Create(F);
    BtnOk.Parent := F;
    BtnOk.Caption := 'Выбрать';
    BtnOk.ModalResult := mrOk;
    BtnOk.Left := 220;
    BtnOk.Top := 240;
    BtnOk.Width := 90;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Caption := 'Отмена';
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Left := 320;
    BtnCancel.Top := 240;
    BtnCancel.Width := 90;

    if F.ShowModal = mrOk then
      if G.Row > 0 then
        Result := G.Cells[0, G.Row];
  finally
    F.Free;
  end;
end;

// Окно выбора состояния готовности заказа.
function TForm1.SelectReadyStatus(var Ready: Boolean): Boolean;
var
  F: TForm;
  L: TLabel;
  C: TComboBox;
  BtnOk, BtnCancel: TButton;
begin
  Result := False;

  F := TForm.Create(nil);
  try
    F.Caption := 'Выбор готовности';
    F.Width := 300;
    F.Height := 155;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Left := 20;
    L.Top := 18;
    L.Caption := 'Состояние готовности заказа:';

    C := TComboBox.Create(F);
    C.Parent := F;
    C.Left := 20;
    C.Top := 42;
    C.Width := 245;
    C.Style := csDropDownList;
    C.Items.Add('Выполнен');
    C.Items.Add('Не выполнен');

    if Ready then
      C.ItemIndex := 0
    else
      C.ItemIndex := 1;

    BtnOk := TButton.Create(F);
    BtnOk.Parent := F;
    BtnOk.Caption := 'ОК';
    BtnOk.ModalResult := mrOk;
    BtnOk.Left := 70;
    BtnOk.Top := 82;
    BtnOk.Width := 75;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Caption := 'Отмена';
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Left := 155;
    BtnCancel.Top := 82;
    BtnCancel.Width := 75;

    if F.ShowModal = mrOk then
    begin
      Ready := C.ItemIndex = 0;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

function TForm1.GetEmployeeFullNameByCode(const Code: string): string;
var
  I: Integer;
  EmployeeItem: TEmployee;
begin
  Result := '';

  for I := 0 to Employees.Count - 1 do
  begin
    EmployeeItem := Employees[I];
    if EmployeeItem.Code = Code then
    begin
      Result := EmployeeItem.FullName;
      Exit;
    end;
  end;
end;

// Обновляет ссылки на сотрудника в квитанциях при смене его кода.
procedure TForm1.UpdateEmployeeCodeInOrders(const OldCode, NewCode: string);
var
  I: Integer;
  OrderItem: TOrder;
begin
  if OldCode = NewCode then
    Exit;

  for I := 0 to Orders.Count - 1 do
  begin
    OrderItem := Orders[I];
    if OrderItem.EmployeeCode = OldCode then
    begin
      OrderItem.EmployeeCode := NewCode;
      Orders[I] := OrderItem;
    end;
  end;
end;

// Отчёт по готовности заказов за текущие сутки.
procedure TForm1.ShowReadyTodayReport;
var
  Groups: TStringList;
  Total, Done, NotDone: TList<Integer>;
  DataRows: TStringList;
  I, Index: Integer;
  Today: TDate;
  OrderItem: TOrder;
begin
  Groups := TStringList.Create;
  Total := TList<Integer>.Create;
  Done := TList<Integer>.Create;
  NotDone := TList<Integer>.Create;
  DataRows := TStringList.Create;
  try
    Today := Date;

    for I := 0 to Orders.Count - 1 do
    begin
      OrderItem := Orders[I];

      if not IsSameRuDate(OrderItem.AcceptDate, Today) then
        Continue;

      Index := Groups.IndexOf(OrderItem.GroupName);

      if Index = -1 then
      begin
        Groups.Add(OrderItem.GroupName);
        Total.Add(0);
        Done.Add(0);
        NotDone.Add(0);
        Index := Groups.Count - 1;
      end;

      Total[Index] := Total[Index] + 1;

      if OrderItem.IsDone then
        Done[Index] := Done[Index] + 1
      else
        NotDone[Index] := NotDone[Index] + 1;
    end;

    for I := 0 to Groups.Count - 1 do
      DataRows.Add(Groups[I] + ';' + IntToStr(Total[I]) + ';' +
        IntToStr(Done[I]) + ';' + IntToStr(NotDone[I]));

    CreateReportWindow(
      'Состояние готовности заказов на текущие сутки',
      'Группа изделия;Всего за сегодня;Выполнено;Не выполнено',
      DataRows
    );
  finally
    Groups.Free;
    Total.Free;
    Done.Free;
    NotDone.Free;
    DataRows.Free;
  end;
end;

// Отчёт о выполненных заказах по сотрудникам за период.
procedure TForm1.ShowEmployeeReport(DateFrom, DateTo: TDate);
var
  I, J, CountDone: Integer;
  D: TDate;
  DataRows: TStringList;
  EmployeeItem: TEmployee;
  OrderItem: TOrder;
begin
  if DateFrom > DateTo then
  begin
    ShowMessage('Дата начала периода не может быть больше даты окончания.');
    Exit;
  end;

  DataRows := TStringList.Create;
  try
    for I := 0 to Employees.Count - 1 do
    begin
      EmployeeItem := Employees[I];
      CountDone := 0;

      for J := 0 to Orders.Count - 1 do
      begin
        OrderItem := Orders[J];

        if not OrderItem.IsDone then
          Continue;

        if OrderItem.EmployeeCode <> EmployeeItem.Code then
          Continue;

        if TryParseDateRu(OrderItem.AcceptDate, D) then
          if (D >= DateFrom) and (D <= DateTo) then
            Inc(CountDone);
      end;

      DataRows.Add(EscapeField(EmployeeItem.Code) + ';' +
        EscapeField(EmployeeItem.FullName) + ';' +
        EscapeField(EmployeeItem.Position) + ';' +
        IntToStr(CountDone));
    end;

    CreateReportWindow(
      'Число выполненных заказов по сотрудникам',
      'Код;ФИО;Должность;Выполнено заказов',
      DataRows
    );
  finally
    DataRows.Free;
  end;
end;

// Создаёт отдельное окно с табличным отчётом.
procedure TForm1.CreateReportWindow(const Title, HeaderLine: string; DataRows: TStrings);
var
  F: TForm;
  G: TStringGrid;
  Headers: TStringList;
  Parts: TStringList;
  I, J: Integer;
begin
  F := TForm.Create(nil);
  Headers := TStringList.Create;
  Parts := TStringList.Create;
  try
    F.Caption := Title;
    F.Width := 700;
    F.Height := 400;
    F.Position := poScreenCenter;

    G := TStringGrid.Create(F);
    G.Parent := F;
    G.Align := alClient;
    G.FixedRows := 1;
    G.FixedCols := 0;
    G.ScrollBars := ssVertical;

    SplitLine(HeaderLine, Headers);
    G.ColCount := Headers.Count;
    G.RowCount := DataRows.Count + 1;

    G.Options := G.Options + [
      goColSizing,
      goFixedVertLine,
      goFixedHorzLine,
      goVertLine,
      goHorzLine
    ];

    for I := 0 to Headers.Count - 1 do
    begin
      G.Cells[I, 0] := Headers[I];
      G.ColWidths[I] := 150;
    end;

    for I := 0 to DataRows.Count - 1 do
    begin
      SplitLine(DataRows[I], Parts);
      for J := 0 to Parts.Count - 1 do
        if J < G.ColCount then
          G.Cells[J, I + 1] := Parts[J];
    end;

    F.ShowModal;
  finally
    Parts.Free;
    Headers.Free;
    F.Free;
  end;
end;

function TForm1.OrderContainsText(const Order: TOrder; const SearchText: string): Boolean;
var
  S: string;
begin
  S := AnsiLowerCase(SearchText);

  Result := Pos(S, AnsiLowerCase(Order.GroupName)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(Order.Brand)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(Order.AcceptDate)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(GetEmployeeFullNameByCode(Order.EmployeeCode))) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(BoolToReadyText(Order.IsDone))) > 0;
end;

function TForm1.EmployeeContainsText(const Employee: TEmployee; const SearchText: string): Boolean;
var
  S: string;
begin
  S := AnsiLowerCase(SearchText);

  Result := Pos(S, AnsiLowerCase(Employee.Code)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(Employee.FullName)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(Employee.Position)) > 0;
  if Result then Exit;

  Result := Pos(S, AnsiLowerCase(IntToStr(Employee.HoursPerDay))) > 0;
end;

function TForm1.BoolToReadyText(Value: Boolean): string;
begin
  if Value then
    Result := 'Выполнен'
  else
    Result := 'Не выполнен';
end;

function TForm1.ReadyTextToBool(const S: string; out Value: Boolean): Boolean;
var
  T: string;
begin
  T := AnsiLowerCase(Trim(S));

  if T = 'выполнен' then
  begin
    Value := True;
    Result := True;
  end
  else if T = 'не выполнен' then
  begin
    Value := False;
    Result := True;
  end
  else
  begin
    Value := False;
    Result := False;
  end;
end;

function TForm1.BoolToFileText(Value: Boolean): string;
begin
  if Value then
    Result := '1'
  else
    Result := '0';
end;

function TForm1.TryParseDateRu(const S: string; out D: TDate): Boolean;
var
  DayPart, MonthPart, YearPart: Integer;
  P1, P2: Integer;
  StrDay, StrMonth, StrYear: string;
begin
  Result := False;
  D := 0;

  P1 := Pos('.', S);
  if P1 = 0 then Exit;

  P2 := PosEx('.', S, P1 + 1);
  if P2 = 0 then Exit;

  StrDay := Copy(S, 1, P1 - 1);
  StrMonth := Copy(S, P1 + 1, P2 - P1 - 1);
  StrYear := Copy(S, P2 + 1, Length(S));

  if not TryStrToInt(StrDay, DayPart) then Exit;
  if not TryStrToInt(StrMonth, MonthPart) then Exit;
  if not TryStrToInt(StrYear, YearPart) then Exit;

  try
    D := EncodeDate(YearPart, MonthPart, DayPart);
    Result := True;
  except
    Result := False;
  end;
end;

function TForm1.IsSameRuDate(const S: string; D: TDate): Boolean;
var
  ParsedDate: TDate;
begin
  Result := TryParseDateRu(S, ParsedDate) and SameDate(ParsedDate, D);
end;

function TForm1.IsDigitsOnly(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';

  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['0'..'9']) then
    begin
      Result := False;
      Exit;
    end;
end;

function TForm1.EmployeeCodeExists(const Code: string; ExceptIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;

  for I := 0 to Employees.Count - 1 do
  begin
    if I = ExceptIndex then
      Continue;

    if Employees[I].Code = Code then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TForm1.GenerateNextEmployeeCode: string;
var
  I, N, MaxCode: Integer;
begin
  MaxCode := 0;

  for I := 0 to Employees.Count - 1 do
  begin
    N := StrToIntDef(Employees[I].Code, 0);
    if N > MaxCode then
      MaxCode := N;
  end;

  Result := Format('%.3d', [MaxCode + 1]);

  while EmployeeCodeExists(Result, -1) do
  begin
    Inc(MaxCode);
    Result := Format('%.3d', [MaxCode + 1]);
  end;
end;

// Разделяет строку файла по символу ';'.
procedure TForm1.SplitLine(const S: string; Parts: TStrings);
var
  I: Integer;
  Current: string;
begin
  Parts.Clear;
  Current := '';

  for I := 1 to Length(S) do
  begin
    if S[I] = ';' then
    begin
      Parts.Add(Current);
      Current := '';
    end
    else
      Current := Current + S[I];
  end;

  Parts.Add(Current);
end;

function TForm1.EscapeField(const S: string): string;
begin
  Result := StringReplace(S, ';', ',', [rfReplaceAll]);
end;

function TForm1.UnescapeField(const S: string): string;
begin
  Result := S;
end;

end.
