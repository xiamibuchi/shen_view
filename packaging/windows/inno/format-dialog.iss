[Code]
var
  FormatDialog: TSetupForm;
  FormatChecks: array of TNewCheckBox;
  ImageTab, ArchiveTab, FormatAll, FormatNone: TNewButton;
  EditingImages: Boolean;

procedure SelectFormatTab(Sender: TObject);
var I, First, Last, CellWidth, Cell, RowHeight: Integer;
begin
  EditingImages := Sender <> ArchiveTab;
  First := 0; Last := ImageList.Items.Count;
  if not EditingImages then begin First := Last; Last := GetArrayLength(FormatChecks); end;
  CellWidth := (FormatDialog.ClientWidth-ScaleX(64)) div 5;
  RowHeight := LimitLayout((FormatDialog.ClientHeight-ScaleY(240)) div 6,ScaleY(32),ScaleY(36));
  for I := 0 to GetArrayLength(FormatChecks)-1 do begin
    FormatChecks[I].Visible := (I >= First) and (I < Last);
    if FormatChecks[I].Visible then begin
      Cell := I-First;
      FormatChecks[I].SetBounds(ScaleX(32)+(Cell mod 5)*CellWidth,ScaleY(152)+(Cell div 5)*RowHeight,CellWidth-ScaleX(4),ScaleY(32));
    end;
  end;
  ImageTab.Font.Style := []; ArchiveTab.Font.Style := [];
  ImageTab.Tag := 0; ArchiveTab.Tag := 0;
  if EditingImages then begin ImageTab.Font.Style := [fsBold]; ImageTab.Tag := 1; end
  else begin ArchiveTab.Font.Style := [fsBold]; ArchiveTab.Tag := 1; end;
  InvalidatePaint(ImageTab.Handle,0,False); InvalidatePaint(ArchiveTab.Handle,0,False);
end;

procedure SelectFormatGroup(Sender: TObject);
var I: Integer;
begin
  for I := 0 to GetArrayLength(FormatChecks)-1 do
    if FormatChecks[I].Visible then FormatChecks[I].Checked := Sender = FormatAll;
end;

procedure ExpandOptions(Sender: TObject);
var I: Integer; Heading, Help: TNewStaticText; Accept, Cancel: TNewButton; Rule: TPanel; Area: TPaintRect;
begin
  FormatDialog := CreateCustomForm(ScaleX(560),ScaleY(460),False,True);
  try
    FormatDialog.BorderStyle := bsNone;
    InstallerWorkArea(WizardForm.Handle,Area);
    FormatDialog.ClientWidth := LimitLayout(Area.Right-Area.Left-ScaleX(16),ScaleX(520),ScaleX(560));
    FormatDialog.ClientHeight := LimitLayout(Area.Bottom-Area.Top-ScaleY(16),ScaleY(432),ScaleY(460));
    FormatDialog.Caption := Tr('自定义打开方式','Customize Open With');
    FormatDialog.Font.Name := WizardForm.Font.Name; FormatDialog.Font.Size := 11;
    if IsDarkInstallMode then FormatDialog.Color := $002B2B2B else FormatDialog.Color := clWhite;
    Heading := TextLabel(FormatDialog,32,20,440,32); Heading.Caption := FormatDialog.Caption;
    Heading.Font.Size := 18; Heading.Font.Style := [fsBold];
    ImageTab := NewButton(FormatDialog,Tr('图片格式','Images'),@SelectFormatTab);
    ImageTab.SetBounds(ScaleX(32),ScaleY(64),ScaleX(112),ScaleY(36));
    ArchiveTab := NewButton(FormatDialog,Tr('压缩包格式','Archives'),@SelectFormatTab);
    ArchiveTab.SetBounds(ScaleX(152),ScaleY(64),ScaleX(120),ScaleY(36));
    FormatAll := NewButton(FormatDialog,Tr('全选','Select all'),@SelectFormatGroup);
    FormatAll.SetBounds(FormatDialog.ClientWidth-ScaleX(208),ScaleY(64),ScaleX(88),ScaleY(36));
    FormatNone := NewButton(FormatDialog,Tr('清空','Clear'),@SelectFormatGroup);
    FormatNone.SetBounds(FormatDialog.ClientWidth-ScaleX(112),ScaleY(64),ScaleX(80),ScaleY(36));
    Help := TextLabel(FormatDialog,32,112,496,32); Help.Width := FormatDialog.ClientWidth-ScaleX(64); Help.Font.Size := 10;
    Help.StyleElements := [seClient,seBorder];
    Help.Caption := Tr('添加到“打开方式”，不更改 Windows 默认应用。','Add to Open With without changing Windows defaults.');
    if IsDarkInstallMode then Help.Font.Color := $00B8B8B8 else Help.Font.Color := $00606060;
    SetArrayLength(FormatChecks,ImageList.Items.Count+ArchiveList.Items.Count);
    for I := 0 to GetArrayLength(FormatChecks)-1 do begin
      if I < ImageList.Items.Count then begin
        FormatChecks[I] := NewCheck(FormatDialog,ImageList.Checked[I],nil);
        FormatChecks[I].Caption := '.' + ImageList.ItemCaption[I];
      end else begin
        FormatChecks[I] := NewCheck(FormatDialog,ArchiveList.Checked[I-ImageList.Items.Count],nil);
        FormatChecks[I].Caption := '.' + ArchiveList.ItemCaption[I-ImageList.Items.Count];
      end;
    end;
    Rule := TPanel.Create(FormatDialog); Rule.Parent := FormatDialog; Rule.BevelOuter := bvNone;
    Rule.ParentBackground := False;
    Rule.StyleElements := [];
    if IsDarkInstallMode then Rule.Color := $00444444 else Rule.Color := $00E8E8E8;
    Rule.SetBounds(ScaleX(32),FormatDialog.ClientHeight-ScaleY(72),FormatDialog.ClientWidth-ScaleX(64),1);
    Cancel := NewButton(FormatDialog,Tr('取消','Cancel'),nil); Cancel.Cancel := True; Cancel.ModalResult := mrCancel;
    Cancel.SetBounds(FormatDialog.ClientWidth-ScaleX(248),FormatDialog.ClientHeight-ScaleY(56),ScaleX(104),ScaleY(40));
    Accept := NewButton(FormatDialog,Tr('确定','OK'),nil); Accept.Default := True; Accept.ModalResult := mrOk;
    Accept.SetBounds(FormatDialog.ClientWidth-ScaleX(136),FormatDialog.ClientHeight-ScaleY(56),ScaleX(104),ScaleY(40));
    StyleButton(Accept,ButtonPrimary); StyleButton(Cancel,ButtonSecondary);
    StyleButton(ImageTab,ButtonTab); StyleButton(ArchiveTab,ButtonTab);
    StyleButton(FormatAll,ButtonSecondary); StyleButton(FormatNone,ButtonSecondary);
    SelectFormatTab(ImageTab);
    StyleFrameWindow(FormatDialog.Handle);
    FormatDialog.FlipAndCenterIfNeeded(True,WizardForm,False);
    KeepWindowInWorkArea(FormatDialog.Handle);
    FormatDialog.ActiveControl := ImageTab;
    if FormatDialog.ShowModal() = mrOk then begin
      for I := 0 to GetArrayLength(FormatChecks)-1 do
        if I < ImageList.Items.Count then ImageList.Checked[I] := FormatChecks[I].Checked
        else ArchiveList.Checked[I-ImageList.Items.Count] := FormatChecks[I].Checked;
      SyncSelection(nil);
    end;
  finally
    ClearOwnedButtons(FormatDialog);
    RemovePaintSubclass(FormatDialog.Handle,FrameCallback,3);
    FormatDialog.Free; FormatDialog := nil; SetArrayLength(FormatChecks,0);
  end;
  WizardForm.ActiveControl := ImageDetails;
end;
