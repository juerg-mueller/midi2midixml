program midi2midixml;

uses
  Vcl.Forms,
  UMidi2Xml in 'UMidi2Xml.pas' {Form1},
  UMidiDataStream in 'UMidiDataStream.pas',
  UMyMemoryStream in 'UMyMemoryStream.pas',
  UMyMidiStream in 'UMyMidiStream.pas',
  UXmlNode in 'UXmlNode.pas',
  UEventArray in 'UEventArray.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
