unit UMidi2Xml;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, ShellApi;

type
  TForm1 = class(TForm)
    Label1: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure WMDropFiles(var Msg: TWMDropFiles); message WM_DROPFILES;
  private
    { Private-Deklarationen }
  public
    procedure ConvertFile(FileName: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  UXmlNode, UMyMidiStream, UMyMemoryStream, UMidiDataStream, UEventArray;

procedure TForm1.FormCreate(Sender: TObject);
begin
  DragAcceptFiles(Self.Handle, true);
end;

procedure TForm1.WMDropFiles(var Msg: TWMDropFiles);
var
  DropH: HDROP;               // drop handle
  DroppedFileCount: Integer;  // number of files dropped
  FileNameLength: Integer;    // length of a dropped file name
  FileName: string;           // a dropped file name
  i: integer;
  ext: string;
begin
  inherited;

  DropH := Msg.Drop;
  try
    DroppedFileCount := DragQueryFile(DropH, $FFFFFFFF, nil, 0);
    if (DroppedFileCount > 0) then
    begin
      for i := 0 to DroppedFileCount-1 do
      begin
        FileNameLength := DragQueryFile(DropH, i, nil, 0);
        SetLength(FileName, FileNameLength);
        DragQueryFile(DropH, i, PChar(FileName), FileNameLength + 1);
        ext := LowerCase(ExtractFileExt(Filename));
        if (ext = '.mid') or
           (ext = '.midi') or
           (ext = '.kar') then
        begin
          ConvertFile(FileName);
        end;
      end;
    end;
  finally
    DragFinish(DropH);
  end;
  Msg.Result := 0;
end;

procedure TForm1.ConvertFile(FileName: string);
var
  stream: TMidiDataStream;
  root, track, eventNode, child: KXmlNode;
  TrackHeader: TTrackHeader;
  event: TMidiEvent;
  i, iTrack: integer;
  Ok: boolean;
  EventArray: TEventArray;
  last_var_len: integer;
  ext: string;
begin
  stream := TMidiDataStream.Create;
  EventArray := TEventArray.Create;
  root := KXmlNode.Create;
  root.Name := 'MIDIFile';
  try
    if FileExists(FileName) then
    begin
      ext := ExtractFileExt(FileName);
      stream.LoadFromFile(FileName);
      SetLength(FileName, Length(FileName) - Length(ext));

      with stream do
      begin
        if not ReadMidiHeader(false) then
          exit;

        root.AppendChildNode('Format', MidiHeader.FileFormat);
        root.AppendChildNode('TrackCount', MidiHeader.TrackCount);
        root.AppendChildNode('TicksPerBeat', MidiHeader.Details.DeltaTimeTicks);
        root.AppendChildNode('TimestampType', 'Delta');

        iTrack := -1;
        while Position + 16 < Size do
        begin
          inc(iTrack);
          if not ReadMidiTrackHeader(TrackHeader, true) then
            break;

          track := root.AppendChildNode('Track');
          track.AppendAttr('Number', iTrack);

          last_var_len := TrackHeader.DeltaTime;
          while ChunkSize > 0 do
          begin
            Event.Clear;
            if not ReadMidiEvent(Event) then
              break;

            if (Event.d1 > 127) or (Event.d2 > 127) then
            begin
              NextByte;
              continue;
            end;

            eventNode := track.AppendChildNode('Event');
            eventNode.AppendChildNode('Delta', last_var_len);
            last_var_len := event.var_len;

            if event.command = $f0 then  // universal system exclusive
            begin
              if Event.d1 = $7f then  // master volume/balance
              begin
                ReadByte; // device id
                Event.d1 := ReadByte;
              end;
              for i := 1 to event.d1-1 do
                ReadByte;
              while ReadByte <> $f7 do ;
              last_var_len := ReadVariableLen;
              eventNode.AppendChildNode('UniversalSystemExclusive');
              continue;
            end;

            Ok := true;
            case Event.Event of
              8, 9:
                begin
                  if (event.Event = 9) and (event.d2 = 0) then
                  begin
                    dec(event.command, $10);
                    event.d2 := 64;
                  end;
                  if (Event.Event = 8) then
                    child := eventNode.AppendChildNode('NoteOff')
                  else
                    child := eventNode.AppendChildNode('NoteOn');
                  child.AppendAttr('Channel', event.Channel);
                  child.AppendAttr('Note', event.d1);
                  child.AppendAttr('Velocity', event.d2);
                end;
              10:
                begin
                  Child := eventNode.AppendChildNode('PolyKeyPressure');
                  Child.AppendAttr('Channel', event.Channel);
                  Child.AppendAttr('Key', event.d1);
                  Child.AppendAttr('Value', event.d2);
                end;
              12:
                begin
                  Child := eventNode.AppendChildNode('ProgramChange');
                  Child.AppendAttr('Channel', event.Channel);
                  Child.AppendAttr('Number', event.d1);
                end;
              11:
                begin
                  Child := eventNode.AppendChildNode('ControlChange');
                  Child.AppendAttr('Channel', event.Channel);
                  Child.AppendAttr('Control', event.d1);
                  Child.AppendAttr('Value', event.d2);
                end;
              13:
                begin
                  Child := eventNode.AppendChildNode('ChannelPressure');
                  Child.AppendAttr('Channel', event.Channel);
                  Child.AppendAttr('Pressure', event.d1);
                  Child.AppendAttr('Value', event.d2);
                end;

              15:
                begin
                  SetLength(event.Bytes, event.d2);
                  for i := 1 to event.d2 do
                  begin
                    event.Bytes[i-1] := ReadByte;
                  end;

                  if event.command = $ff then
                  begin
                    if (event.d2 > 0) then
                      last_var_len := ReadVariableLen;

                    case event.d1 of
                      1: eventNode.AppendChildNode('TextEvent', event.str);
                      2: eventNode.AppendChildNode('CopyrightNotice', event.str);
                      3: eventNode.AppendChildNode('TrackName', trim(event.str));
                      4: eventNode.AppendChildNode('InstrumentName', event.str);
                      5: eventNode.AppendChildNode('Lyric', event.str);
                      6: eventNode.AppendChildNode('Marker', event.str);
                      7: eventNode.AppendChildNode('CuePoint', event.str);
                      $20:
                        begin
                          child := eventNode.AppendChildNode('MIDIChannelPrefix');
                          child.AppendAttr('Value', event.int);
                        end;
                      $2f: eventNode.AppendChildNode('EndOfTrack');
                      $51:
                        begin
                          child := eventNode.AppendChildNode('SetTempo');
                          child.AppendAttr('Value', event.int);
                        end;
                      $58:
                        begin
                          child := eventNode.AppendChildNode('TimeSignature');
                          Child.AppendAttr('Numerator', event.Bytes[0]);
                          Child.AppendAttr('LogDenominator', event.Bytes[1]);
                          Child.AppendAttr('MIDIClocksPerMetronomeClick', event.Bytes[2]);
                          Child.AppendAttr('ThirtySecondsPer24Clocks', event.Bytes[3]);
                        end;
                      $59:
                        begin
                          child := eventNode.AppendChildNode('KeySignature');
                          Child.AppendAttr('Fifths', event.Bytes[0]);
                          Child.AppendAttr('Mode', event.Bytes[1]);
                        end;
                      else Ok := false;
                    end;
                  end;
               end;
               else Ok := false;
            end;
            if not Ok then
            begin
              eventNode.AppendAttr('command', '$' + IntToHex(event.command));
              eventNode.AppendAttr('d1', event.d1);
              eventNode.AppendAttr('d2', event.d2);
            end;
            if event.IsEndOfTrack then
              break;

          end;
        end;
        if FileExists(FileName + '.midixml') and
           (Application.MessageBox(PChar(FileName + '.midixml exists! Overwrite it?'),
                                'Overwrite?', MB_YESNO) <> ID_YES) then
          exit;
        root.SaveToXmlFile(FileName + '.midixml',
            '<?xml version="1.0" encoding="UTF-8"?>'#13#10);
      end;
      if stream.MakeEventArray(EventArray, true) then
        EventArray.SaveSimpleMidiToFile(FileName + '.txt', true);
    end;
  finally
    stream.Free;
    root.Free;
    EventArray.Free;
  end;
end;

end.
