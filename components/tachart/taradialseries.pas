{

 *****************************************************************************
 *                                                                           *
 *  See the file COPYING.modifiedLGPL.txt, included in this distribution,    *
 *  for details about the copyright.                                         *
 *                                                                           *
 *  This program is distributed in the hope that it will be useful,          *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of           *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                     *
 *                                                                           *
 *****************************************************************************

 Authors: Alexander Klenin

}

unit TARadialSeries;

{$H+}

interface

uses
  Classes, Graphics, SysUtils, Types,
  TACustomSeries, TALegend;

type
  TLabelParams = record
    FSize: TSize;
    FText: String;
  end;

  TPieSlice = record
    FAngle: Double;
    FOffset: TPoint;
  end;

  { TCustomPieSeries }

  TCustomPieSeries = class(TChartSeries)
  private
    FCenter: TPoint;
    FLabels: array of TLabelParams;
    FRadius: Integer;
    FSlices: array of TPieSlice;
    FExploded: Boolean;
    procedure Measure(ACanvas: TCanvas);
    procedure SetExploded(const AValue: Boolean);
    function SliceColor(AIndex: Integer): TColor;
  protected
    procedure AfterAdd; override;
    procedure GetLegendItems(AItems: TChartLegendItems); override;
  public
    function AddPie(Value: Double; Text: String; Color: TColor): Longint;
    procedure Draw(ACanvas: TCanvas); override;
    function FindContainingSlice(const APoint: TPoint): Integer;

    // Offset slices away from center based on X value.
    property Exploded: Boolean read FExploded write SetExploded default false;
    property Source;
  end;

implementation

uses
  Math, GraphMath,
  TAChartUtils, TADrawUtils, TASources;

{ TCustomPieSeries }

function TCustomPieSeries.AddPie(Value: Double; Text: String; Color: TColor): Longint;
begin
  Result := AddXY(GetXMaxVal + 1, Value, Text, Color);
end;

procedure TCustomPieSeries.AfterAdd;
begin
  inherited;
  // disable axis when we have TPie series
  ParentChart.LeftAxis.Visible := false;
  ParentChart.BottomAxis.Visible := false;
end;

procedure TCustomPieSeries.Draw(ACanvas: TCanvas);

  function LabelExtraDist(AAngle: Double; AIndex: Integer): Double;
  const
    ALMOST_INF = 1e10;
  var
    z, e: TDoublePoint;
    r: TDoubleRect;
  begin
    z := ZeroDoublePoint;
    e := RotatePoint(DoublePoint(ALMOST_INF, 0), AAngle + Pi);
    r.a.X := -FLabels[AIndex].FSize.cx / 2;
    r.b.X := -r.a.X;
    r.a.Y := -FLabels[AIndex].FSize.cy / 2;
    r.b.Y := -r.a.Y;
    LineIntersectsRect(z, e, r);
    Result := Norm([e.X, e.Y]);
  end;

var
  i: Integer;
  prevAngle: Double = 0;
  ed, sliceCenterAngle: Double;
  c: TPoint;
  prevLabelPoly: TPointArray = nil;
begin
  if IsEmpty then exit;

  Measure(ACanvas);

  for i := 0 to Count - 1 do begin
    ACanvas.Pen.Color := clBlack;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := SliceColor(i);

    with FSlices[i] do begin
      sliceCenterAngle := (prevAngle + FAngle / 2);
      c := FCenter + FOffset;
      ACanvas.RadialPie(
        c.x - FRadius, c.y - FRadius, c.x + FRadius, c.y + FRadius,
        RadToDeg16(prevAngle), RadToDeg16(FAngle));
      prevAngle += FAngle;
    end;

    if not Marks.IsMarkLabelsVisible or (FLabels[i].FText = '') then
      continue;
    ed := LabelExtraDist(sliceCenterAngle, i);
    Marks.DrawLabel(
      ACanvas,
      LineEndPoint(c, RadToDeg16(sliceCenterAngle), FRadius),
      LineEndPoint(c, RadToDeg16(sliceCenterAngle), FRadius + Marks.Distance + ed),
      FLabels[i].FText, prevLabelPoly);
  end;
end;

function TCustomPieSeries.FindContainingSlice(const APoint: TPoint): Integer;
var
  prevAngle: Double = 0;
  c: TPoint;
  pointAngle: Double;
begin
  if IsEmpty then exit(-1);

  for Result := 0 to Count - 1 do
    with FSlices[Result] do begin
      c := APoint - FCenter - FOffset;
      pointAngle := ArcTan2(-c.Y, c.X);
      if pointAngle < 0 then
        pointAngle += 2 * Pi;
      if
        InRange(pointAngle - prevAngle, 0, FAngle) and
        (Sqr(c.X) + Sqr(c.Y) <= Sqr(FRadius))
      then
        exit;
      prevAngle += FAngle;
    end;
  Result := -1;
end;

procedure TCustomPieSeries.GetLegendItems(AItems: TChartLegendItems);
var
  i: Integer;
  br: TLegendItemBrushRect;
  ps: TLegendItemPieSlice;
begin
  case Legend.Multiplicity of
    lmSingle: begin
      br := TLegendItemBrushRect.Create(nil, Title);
      br.Color := SliceColor(0);
      AItems.Add(br);
    end;
    lmPoint:
      for i := 0 to Count - 1 do begin
        ps := TLegendItemPieSlice.Create(FormattedMark(i));
        ps.Color := SliceColor(i);
        AItems.Add(ps);
      end;
  end;
end;

procedure TCustomPieSeries.Measure(ACanvas: TCanvas);
const
  MARGIN = 8;
var
  i: Integer;
  m: TPoint = (X: 0; Y: 0);
  di: PChartDataItem;
  prevAngle: Double = 0;
begin
  SetLength(FLabels, Count);
  SetLength(FSlices, Count);
  for i := 0 to Count - 1 do
    with FLabels[i] do begin
      FText := FormattedMark(i);
      FSize := Marks.MeasureLabel(ACanvas, FText);
      m.X := Max(m.X, FSize.cx);
      m.Y := Max(m.Y, FSize.cy);
    end;

  FCenter := CenterPoint(ParentChart.ClipRect);
  // Reserve space for labels.
  m := ParentChart.ClipRect.BottomRight - FCenter - m;
  FRadius := Min(m.X, m.Y);
  if Marks.IsMarkLabelsVisible then
    FRadius -= Marks.Distance;
  FRadius := Max(FRadius - MARGIN, 0);
  if Exploded then
    FRadius := Trunc(FRadius / (Max(Source.Extent.b.X, 0) + 1));

  for i := 0 to Count - 1 do begin
    di := Source[i];
    with FSlices[i] do begin
      FAngle := CycleToRad(di^.Y / Source.ValuesTotal);
      FOffset := Point(0, 0);
      if Exploded and (di^.X > 0) then begin
        FOffset.X := Round(FRadius * di^.X);
        FOffset := RotatePoint(FOffset, prevAngle + FAngle / 2);
        FOffset.Y := - FOffset.Y;
      end;
      prevAngle += FAngle;
    end;
  end;
end;

procedure TCustomPieSeries.SetExploded(const AValue: Boolean);
begin
  if FExploded = AValue then exit;
  FExploded := AValue;
  UpdateParentChart;
end;

function TCustomPieSeries.SliceColor(AIndex: Integer): TColor;
begin
  Result :=
    ColorOrDefault(Source[AIndex]^.Color, Colors[AIndex mod High(Colors) + 1]);
end;

end.

