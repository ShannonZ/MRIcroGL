unit texture2raycast;
{$IFDEF FPC}{$mode objfpc}{$H+}{$ENDIF}
interface
{$include opts.inc}
uses
{$IFDEF DGL} dglOpenGL, {$ELSE DGL} {$IFDEF COREGL}gl_core_matrix, glcorearb, {$ELSE} gl,glext, {$ENDIF}  {$ENDIF DGL}
  {$IFNDEF FPC} Windows, {$ENDIF}  raycast_common, {$IFDEF COREGL} raycast_core, {$ELSE} raycast_legacy, {$ENDIF}
{$IFDEF USETRANSFERTEXTURE}texture_3d_unit_transfertexture, {$ELSE} texture_3d_unit,{$ENDIF}
  shaderu, clut,dialogs,Classes,define_types, sysUtils;
procedure CreateGradientVolume (var Tex: TTexture; var gradientVolume : GLuint; var inRGBA : Bytep0; isOverlay: boolean);
procedure CreateVolumeGL (var Tex: TTexture; var volumeID    : GLuint; ptr: PChar);
Procedure LoadTTexture(var Tex: TTexture);
function CheckTextureMemory (var Tex: TTexture; isRGBA: boolean): boolean;

implementation
uses
{$IFDEF FPC} LCLIntf,{$ENDIF}
//{$IFDEF ENABLEOVERLAY}overlay,  {$ENDIF}
mainunit;

 type
    TRGBA = packed record //Next: analyze Format Header structure
    R,G,B,A : byte;
  end;
  tVolB = array of byte;
  tVolW = array of word;
  tVolS = array of single;
  tVolRGBA = array of TRGBA;//longword;

const
  kRGBAclear : TRGBA = (r: 0; g: 0; b: 0; a:0);
{$DEFINE GRADIENT_PRENORM}
//pre-normalizing our data allows us to avoids the "normalize" in GLSL
//  gradientSample.rgb = normalize(gradientSample.rgb*2.0 - 1.0);
//it is a bit slower and does provide a bit less precision
//in 2017 we switched to the pre-norm so that the CPU and GLSL gradients match each other
{$IFDEF GRADIENT_PRENORM}
Function XYZIx (X1,X2,Y1,Y2,Z1,Z2: single): TRGBA;
//input voxel intensity to the left,right,anterior,posterior,inferior,superior and center
// Output RGBA image where values correspond to X,Y,Z gradients and ImageIntensity
var
  X,Y,Z,Dx: single;
begin
  Result := kRGBAclear;
  X := X1-X2;
  Y := Y1-Y2;
  Z := Z1-Z2;
  Dx := sqrt(X*X+Y*Y+Z*Z);
  if Dx = 0 then
    exit;  //no gradient - set intensity to zero.
  result.r :=round((X/(Dx*2)+0.5)*255);
  result.g :=round((Y/(Dx*2)+0.5)*255);
  result.B := round((Z/(Dx*2)+0.5)*255);
end;
{$ELSE GRADIENT_PRENORM}
Function XYZIx (X1,X2,Y1,Y2,Z1,Z2: single): TRGBA; {$IFDEF FPC} inline; {$ENDIF}
//faster, more precise version of XYZI for computation, but requires "normalize" for display
var
  X,Y,Z,Dx: single;
begin
  Result := kRGBAclear;
  X := X1-X2;
  Y := Y1-Y2;
  Z := Z1-Z2;
  Dx := abs(X);
  if abs(Y) > Dx then Dx := abs(Y);
  if abs(Z) > Dx then Dx := abs(Z);
  if Dx = 0 then
    exit;  //no gradient - set intensity to zero.                      Calculate_Transfer_Function
  Dx := Dx * 2; //scale vector lengths from 0..0.5, so we can pack -1..+1 in the range 0..255
  result.r :=round((X/Dx+0.5)*255);           //X
  result.g :=round((Y/Dx+0.5)*255); //Y
  result.B := round((Z/Dx+0.5)*255); //Z
end;
{$ENDIF GRADIENT_PRENORM}

{$DEFINE SOBEL}
{$IFDEF SOBEL} //use SOBEL
function estimateGradients (rawData: tVolB; Xsz,Ysz, I : integer; var GradMag: single): TRGBA; {$IFDEF FPC} inline; {$ENDIF}
//this computes intensity gradients using 3D Sobel filter.
//This is slower than central difference but more accurate
//http://www.aravind.ca/cs788h_Final_Project/gradient_estimators.htm
var
  Y,Z,J: integer;
  Xp,Xm,Yp,Ym,Zp,Zm: single;
begin
  Y := XSz; //each row is X voxels
  Z := YSz*XSz; //each plane is X*Y voxels
  //X:: cols: +Z +0 -Z, rows -Y +0 +Y
  J := I+1;
  Xp := rawData[J-Y+Z]+3*rawData[J-Y]+rawData[J-Y-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+Y+Z]+3*rawData[J+Y]+rawData[J+Y-Z];
  J := I-1;
  Xm := rawData[J-Y+Z]+3*rawData[J-Y]+rawData[J-Y-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+Y+Z]+3*rawData[J+Y]+rawData[J+Y-Z];
  //Y:: cols: +Z +0 -Z, rows -X +0 +X
  J := I+Y;
  Yp := rawData[J-1+Z]+3*rawData[J-1]+rawData[J-1-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+1+Z]+3*rawData[J+1]+rawData[J+1-Z];
  J := I-Y;
  Ym := rawData[J-1+Z]+3*rawData[J-1]+rawData[J-1-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+1+Z]+3*rawData[J+1]+rawData[J+1-Z];
  //Z:: cols: +Z +0 -Z, rows -X +0 +X
  J := I+Z;
  Zp := rawData[J-Y+1]+3*rawData[J-Y]+rawData[J-Y-1]
        +3*rawData[J+1]+6*rawData[J]+3*rawData[J-1]
        +rawData[J+Y+1]+3*rawData[J+Y]+rawData[J+Y-1];
  J := I-Z;
  Zm := rawData[J-Y+1]+3*rawData[J-Y]+rawData[J-Y-1]
        +3*rawData[J+1]+6*rawData[J]+3*rawData[J-1]
        +rawData[J+Y+1]+3*rawData[J+Y]+rawData[J+Y-1];
  result := XYZIx (Xm,Xp,Ym,Yp,Zm,Zp);
  GradMag :=  sqrt( sqr(Xm-Xp)+sqr(Ym-Yp)+sqr(Zm-Zp));//gradient magnitude
  //GradMag :=  abs( Xm-Xp)+abs(Ym-Yp)+abs(Zm-Zp);//gradient magnitude
end;
{$ELSE} //if SOBEL else Central difference
function estimateGradients (rawData: tVolB; Xsz,Ysz, I : integer; var GradMag: single): TRGBA; inline;
//slightly faster than Sobel
var
Y,Z: integer;
Xp,Xm,Yp,Ym,Zp,Zm: single;
begin
  //GradMag := 0;//gradient magnitude
  //Result := kRGBAclear;
  //if rawData[i] < 1 then
  //  exit; //intensity less than threshold: make invisible
  Y := XSz; //each row is X voxels
  Z := YSz*XSz; //each plane is X*Y voxels
  //X:: cols: +Z +0 -Z, rows -Y +0 +Y
  Xp := rawData[I+1];
  Xm := rawData[I-1];
  //Y:: cols: +Z +0 -Z, rows -X +0 +X
  Yp := rawData[I+Y];
  Ym := rawData[I-Y];
  //Z:: cols: +Z +0 -Z, rows -X +0 +X
  Zp := rawData[I+Z];
  Zm := rawData[I-Z];
  //result := XYZIx (Xm,Xp,Ym,Yp,Zm,Zp,rawData[I]);
  result := XYZIx (Xm,Xp,Ym,Yp,Zm,Zp);
  GradMag :=  abs( Xm-Xp)+abs(Ym-Yp)+abs(Zm-Zp);//gradient magnitude
end;
{$ENDIF}

procedure NormVol (var Vol: tVolS);
var
  n,i: integer;
  mx,mn: single;
begin
  n := length(Vol);
  if n < 1 then
    exit;
  mx := Vol[0];
  mn := Vol[0];
  for i := 0 to (n-1) do begin
    if Vol[i] > mx then
      mx := Vol[i];
    if Vol[i] < mn then
      mn := Vol[i];
  end;
  if mx = mn then
    exit;
  mx := mx-mn;//range
  for i := 0 to (n-1) do
    Vol[i] := (Vol[i]-mn)/mx;
end;

(*procedure SmoothVol (var rawData: tVolB; lXdim,lYdim,lZdim: integer);
var
  lSmoothImg,lSmoothImg2: tVolW;
  lSliceSz,lnVox,i: integer;
begin
  lSliceSz := lXdim*lYdim;
  lnVox := lSliceSz*lZDim;
  if (lnVox < 0) or (lXDim < 3) or (lYDim < 3) or (lZDim < 3) then exit;
  setlength(lSmoothImg,lnVox);
  setlength(lSmoothImg2,lnVox);
  //smooth with X neighbors (left and right) stride = 1
  for i := 0 to (lnVox-2) do //output x5 input
      lSmoothImg[i] := rawData[i-1] + (rawData[i] * 3) + rawData[i+1];
  //smooth with Y neighbors (anterior, posterior) stride = Xdim
  for i := lXdim to (lnVox-lXdim-1) do  //output x5 (5x5=25) input
      lSmoothImg2[i] := lSmoothImg[i-lXdim] + (lSmoothImg[i] * 3) + lSmoothImg[i+lXdim];
  //smooth with Z neighbors (inferior, superior) stride = lSliceSz
    for i := lSliceSz to (lnVox-lSliceSz-1) do  // x5 input (25*5=125)
      rawData[i] := (lSmoothImg2[i-lSliceSz] + (lSmoothImg2[i] * 3) + lSmoothImg2[i+lSliceSz]) div 125;
  lSmoothImg := nil;
  lSmoothImg2 := nil;
end; *)

procedure SmoothVol (var rawData: tVolB; lXdim,lYdim,lZdim: integer);
var
  lSmoothImg,lSmoothImg2: tVolW;
  lSliceSz,lnVox,i: integer;
begin
  //exit; //blurring the gradients can hurt low resolution images, e.g. mni2009_256 with glass shader
  lSliceSz := lXdim*lYdim;
  lnVox := lSliceSz*lZDim;
  if (lnVox < 0) or (lXDim < 3) or (lYDim < 3) or (lZDim < 3) then exit;
  setlength(lSmoothImg,lnVox);
  setlength(lSmoothImg2,lnVox);
  //smooth with X neighbors (left and right) stride = 1
  lSmoothImg[0] := rawData[0];
  lSmoothImg[lnVox-1] := rawData[lnVox-1];
  for i := 1 to (lnVox-2) do //output *4 input (8bit->10bit)
      lSmoothImg[i] := rawData[i-1] + (rawData[i] shl 1) + rawData[i+1];
  //smooth with Y neighbors (anterior, posterior) stride = Xdim
  for i := lXdim to (lnVox-lXdim-1) do  //output *4 input (10bit->12bit)
      lSmoothImg2[i] := lSmoothImg[i-lXdim] + (lSmoothImg[i] shl 1) + lSmoothImg[i+lXdim];
  //smooth with Z neighbors (inferior, superior) stride = lSliceSz
    for i := lSliceSz to (lnVox-lSliceSz-1) do  // *4 input (12bit->14bit) , >> 6 for 8 bit output
      rawData[i] := (lSmoothImg2[i-lSliceSz] + (lSmoothImg2[i] shl 1) + lSmoothImg2[i+lSliceSz]) shr 6;
  lSmoothImg := nil;
  lSmoothImg2 := nil;
end;

procedure CreateGradientVolumeCPU (var VolRGBA: tVolRGBA; dim1, dim2, dim3: integer);
//compute gradients for each voxel... Output texture in form RGBA
//  RGB will represent as normalized X,Y,Z gradient vector:  Alpha will store gradient magnitude
const
  kEdgeSharpness = 255;//value 1..255: 1=all edges transparent, 255=edges very opaque
var
  X, Y,Z,Index,nVox, dim1x2 : Integer;
  VolData: tVolB;
  GradMagS: tVolS;
Begin
  nVox := dim1*dim2*dim3;
  SetLength (VolData,nVox);
  for Index := 0 to (nVox-1) do //we can not compute gradients for image edges, so initialize volume so all voxels are transparent
    VolData[Index] := VolRGBA[Index].A;
  SmoothVol (VolData, dim1,dim2, dim3); //blur data
  SetLength (GradMagS,nVox); //store magnitude values
  for Index := 0 to (nVox-1) do //we can not compute gradients for image edges, so initialize volume so all voxels are transparent
    VolRGBA[Index] := kRGBAclear;
  for Index := 0 to (nVox-1) do //we can not compute gradients for image edges, so initialize volume so all voxels are transparent
    GradMagS[Index] := 0;
  //The following trick saves very little time
  //Z := (Tex.FiltDim[1]*Tex.FiltDim[2]) + Tex.FiltDim[1] + 1;
  //for Index := Z to (nVox - Z) do
  //  if (VolData[Index] <> 0) then
  //   VolRGBA[Index] := estimateGradients (VolData, Tex.FiltDim[1],Tex.FiltDim[2], Index,GradMagS[Index]);
  dim1x2 := dim1 * dim2; //slice size
  for Z := 1 To dim3 - 2 do  //for X,Y,Z dimensions indexed from zero, so := 1 gives 1 voxel border
    for Y := 1 To dim2 - 2 do
      for X := 1 To dim1 - 2 do begin
        Index := (Z * dim1x2) + (Y * dim1) + X;
        //estimate gradients using Sobel or  Central Difference  (depending on DEFINE SOBEL)
        if (VolData[Index] <> 0) then
           VolRGBA[Index] := estimateGradients (VolData, dim1,dim2, Index,GradMagS[Index]);
      end;//X
  VolData := nil;//FREE ----
  //next: generate normalized gradient magnitude values
  NormVol (GradMagS);//FREE ----
  for Index := 0 to (nVox-1) do
    VolRGBA[Index].A := round(GradMagS[Index]*kEdgeSharpness);
  GradMagS := nil;
end;


function CheckTextureMemory (var Tex: TTexture; isRGBA: boolean): boolean;
var
  i : Integer;
begin
  //Use PROXY to see if video card can support a texture...
  //http://www.opengl.org/resources/faq/technical/texture.htm
  //glTexImage3D(GL_PROXY_TEXTURE_2D, level, internalFormat,  width, height, border, format, type, NULL);
  //Note the pixels parameter is NULL, because OpenGL doesn't load texel data when the target parameter is GL_PROXY_TEXTURE_2D. Instead, OpenGL merely considers whether it can accommodate a texture of the specified size and description. If the specified texture can't be accommodated, the width and height texture values will be set to zero. After making a texture proxy call, you'll want to query these values as follows:
  result := false;
  if not isRGBA then
  {$IFDEF COREGL}
  glTexImage3D(GL_PROXY_TEXTURE_3D, 0, GL_RED, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0,GL_RED, GL_UNSIGNED_BYTE, nil)
  {$ELSE}
  glTexImage3D(GL_PROXY_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0,GL_ALPHA, GL_UNSIGNED_BYTE, nil)
  {$ENDIF}
  else
    glTexImage3D (GL_PROXY_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0,GL_RGBA, GL_UNSIGNED_BYTE, nil);
  glGetTexLevelParameteriv(GL_PROXY_TEXTURE_3D, 0, GL_TEXTURE_WIDTH, @i);
  if i < 1 then begin
    showdebug('Your video card is unable to load an image that is this large: '+inttostr(Tex.FiltDim[1]));
    exit;
  end;
  result := true;
end;


procedure CreateGradientVolume (var Tex: TTexture; var gradientVolume : GLuint; var inRGBA : Bytep0; isOverlay: boolean);
//calculate gradients on the CPU or GPU (using GLSL)
var
  gradRGBA: tVolRGBA;
  starttime: dword;
begin
  //copy memory to GPU's VRAM
  glDeleteTextures(1,@gradientVolume);
  if not CheckTextureMemory(Tex,true) then exit;
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  glGenTextures(1, @gradientVolume);
  glBindTexture(GL_TEXTURE_3D, gradientVolume);
  {$IFNDEF COREGL}glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE); {$ENDIF}
  //glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  //glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); //FCX
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_BORDER);//?
  startTime := gettickcount;
  if  gPrefs.FasterGradientCalculations then begin //123454
     if isOverlay then
        Tex.updateOverlayGradientsGLSL := true
     else
        Tex.updateBackgroundGradientsGLSL := true;
     glTexImage3D(GL_TEXTURE_3D, 0,GL_RGBA, Tex.FiltDim[1], Tex.FiltDim[2],Tex.FiltDim[3],0, GL_RGBA, GL_UNSIGNED_BYTE,PChar(inRGBA));
     //glTexImage3D(GL_TEXTURE_3D, 0,GL_RGBA, Tex.FiltDim[1], Tex.FiltDim[2],Tex.FiltDim[3],0, GL_RGBA, GL_UNSIGNED_BYTE,PChar(Tex.FiltImg));
  end else begin
    try
      SetLength (gradRGBA, 4*Tex.FiltDim[1]*Tex.FiltDim[2]*Tex.FiltDim[3]);
    except
      //ReleaseContext;
      {$IFDEF Linux}
      ShowMessage ('Memory exhausted: perhaps this image is too large. Restart with the CONTROL key down to reset');
      {$ELSE}
      ShowMessage ('Memory exhausted: perhaps this image is too large. Restart with the SHIFT key down to reset');
      {$ENDIF}
   end;
    //Move(Tex.FiltImg^,gradRGBA[0], 4*Tex.FiltDim[1]*Tex.FiltDim[2]*Tex.FiltDim[3]);//src, dest, bytes
    Move(inRGBA^,gradRGBA[0], 4*Tex.FiltDim[1]*Tex.FiltDim[2]*Tex.FiltDim[3]);//src, dest, bytes
    CreateGradientVolumeCPU (gradRGBA,Tex.FiltDim[1],Tex.FiltDim[2],Tex.FiltDim[3]);
    glBindTexture(GL_TEXTURE_3D, gradientVolume);
    glTexImage3D(GL_TEXTURE_3D, 0,GL_RGBA, Tex.FiltDim[1], Tex.FiltDim[2],Tex.FiltDim[3],0, GL_RGBA, GL_UNSIGNED_BYTE,PChar(gradRGBA)  );
    SetLength(gradRGBA,0);
    if gPrefs.Debug then
         GLForm1.Caption := 'CPU gradient '+inttostr(gettickcount-startTime)+'ms ';
  end;
end;

{$IFDEF USETRANSFERTEXTURE}

Procedure iCreateColorTable (var transferTexture : GLuint; var CLUTrec: TCLUTrec);// Load image data
var lCLUT: TLUT;
begin
  GenerateLUT(CLUTrec, lCLUT);
  //if transferTexture <> 0 then
      glDeleteTextures(1,@transferTexture);
  glGenTextures(1, @transferTexture);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glBindTexture(GL_TEXTURE_1D, transferTexture);
  glTexParameterf(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_CLAMP);
  glTexParameterf(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameterf(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, @lCLUT[0]);
end;
{$ENDIF}


(* CreateVolumeGL (var Tex: TTexture; var volumeID    : GLuint; ptr: PChar);
begin
  glDeleteTextures(1,@volumeID);
  if not CheckTextureMemory(Tex,true) then exit;
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  glGenTextures(1, @volumeID);
  glBindTexture(GL_TEXTURE_3D, volumeID);
  //if gPrefs.InterpolateView then begin
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  //end else begin
  //    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); //awful aliasing
  //    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); //awful aliasing
  //end;
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_BORDER);//?
  //  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); //awful aliasing
  //  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); //awful aliasing
  if Tex.DataType = GL_RGBA then begin
    {$IFDEF Darwin}
    //glTexImage3D   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, PChar(Tex.OverlayImgRGBA)); //OverlayImgRGBA
    glTexImage3D   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, ptr); //OverlayImgRGBA
    {$ELSE}
    //glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, PChar(Tex.OverlayImgRGBA));
    glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, ptr);
    {$ENDIF}
  end else begin
    {$IFDEF Darwin}
    //glTexImage3D   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, PChar(Tex.FiltImg));
    glTexImage3D   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, ptr);
    {$ELSE}
    //glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, PChar(Tex.FiltImg));
    glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, ptr);
    {$ENDIF}
  end;
end;   *)

procedure CreateVolumeGL (var Tex: TTexture; var volumeID    : GLuint; ptr: PChar);
begin
  glDeleteTextures(1,@volumeID);
  if not CheckTextureMemory(Tex,true) then exit;
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  glGenTextures(1, @volumeID);
  glBindTexture(GL_TEXTURE_3D, volumeID);
  //if gPrefs.InterpolateView then begin
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  //end else begin
  //    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); //awful aliasing
  //    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); //awful aliasing
  //end;
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);//?
  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_BORDER);//?
  //  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); //awful aliasing
  //  glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); //awful aliasing
  if Tex.DataType = GL_RGBA then begin
    {$IFDEF Darwin}
    //glTexImage3D   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, PChar(Tex.OverlayImgRGBA)); //OverlayImgRGBA
    glTexImage3D   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, ptr); //OverlayImgRGBA
    {$ELSE}
    //glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, PChar(Tex.OverlayImgRGBA));
    glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, ptr);
    {$ENDIF}
  end else begin
    {$IFDEF Darwin}
     {$IFDEF COREGL}
     glTexImage3D   (GL_TEXTURE_3D, 0, GL_RED, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_RED, GL_UNSIGNED_BYTE, ptr);
     {$ELSE}
     glTexImage3D   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, ptr);
     {$ENDIF}
    {$ELSE}
    glTexImage3D(GL_TEXTURE_3D, 0, GL_INTENSITY, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, ptr);

    //glTexImage3DExt   (GL_TEXTURE_3D, 0, GL_ALPHA8, Tex.FiltDim[1], Tex.FiltDim[2], Tex.FiltDim[3], 0, GL_ALPHA, GL_UNSIGNED_BYTE, ptr);
    {$ENDIF}
  end;
end;

Procedure LoadTTexture(var Tex: TTexture);
begin
     CreateVolumeGL (Tex, gRayCast.intensityTexture3D, PChar(Tex.FiltImg));
     CreateGradientVolume (Tex, gRayCast.gradientTexture3D, Tex.FiltImg, false);
end;

end.

