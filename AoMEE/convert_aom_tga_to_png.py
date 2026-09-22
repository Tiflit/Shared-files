from __future__ import annotations
import csv, hashlib, sys
from pathlib import Path
from PIL import Image

def decode_tga(path: Path):
    data = path.read_bytes()
    if len(data) < 18:
        raise ValueError("TGA shorter than 18-byte header")
    h=data[:18]
    image_id_length=h[0]; color_map_type=h[1]; image_type=h[2]
    color_map_length=int.from_bytes(h[5:7],"little"); color_map_bits=h[7]
    width=int.from_bytes(h[12:14],"little"); height=int.from_bytes(h[14:16],"little")
    bpp=h[16]; descriptor=h[17]
    if color_map_type != 0: raise ValueError("Color-mapped TGAs are not supported")
    if image_type not in (2,10): raise ValueError(f"Unsupported TGA image type {image_type}")
    if bpp not in (24,32): raise ValueError(f"Unsupported TGA bit depth {bpp}")
    if width <= 0 or height <= 0: raise ValueError(f"Invalid dimensions {width}x{height}")
    bpp_bytes=bpp//8
    left_to_right=not bool(descriptor & 0x10)
    top_to_bottom=bool(descriptor & 0x20)
    offset=18+image_id_length
    if color_map_type != 0:
        offset += color_map_length*((color_map_bits+7)//8)
    if offset > len(data): raise ValueError("Image data starts beyond EOF")
    total=width*height
    out=bytearray(total*4)
    def put(i,pix):
        row=i//width; col=i%width
        x=col if left_to_right else width-1-col
        y=row if top_to_bottom else height-1-row
        j=(y*width+x)*4
        if bpp==32: b,g,r,a=pix
        else: b,g,r=pix; a=255
        out[j:j+4]=bytes((r,g,b,a))
    pos=offset
    def pixel():
        nonlocal pos
        if pos+bpp_bytes>len(data): raise ValueError("Pixel data is truncated")
        p=data[pos:pos+bpp_bytes]; pos+=bpp_bytes; return p
    read=0
    if image_type==2:
        need=total*bpp_bytes
        if pos+need>len(data): raise ValueError(f"Uncompressed payload truncated: {len(data)-pos} < {need}")
        for i in range(total): put(i,pixel()); read+=1
    else:
        while read<total:
            if pos>=len(data): raise ValueError(f"RLE stream ended at {read}/{total} pixels")
            ph=data[pos]; pos+=1; count=(ph&0x7f)+1
            if read+count>total: raise ValueError(f"RLE packet exceeds image: {read}+{count}>{total}")
            if ph&0x80:
                p=pixel()
                for _ in range(count): put(read,p); read+=1
            else:
                for _ in range(count): put(read,pixel()); read+=1
    if read!=total: raise ValueError(f"Decoded {read} pixels, expected {total}")
    rgba=bytes(out)
    return Image.frombytes("RGBA",(width,height),rgba), {
        "Width":width,"Height":height,"ImageType":image_type,"BitsPerPixel":bpp,
        "DecodedPixels":read,"RGBA_SHA256":hashlib.sha256(rgba).hexdigest()
    }

def main():
    if len(sys.argv)!=3:
        print("Usage: convert_aom_tga_to_png.py <source_root> <png_root>"); return 2
    src=Path(sys.argv[1]).resolve(); dst=Path(sys.argv[2]).resolve()
    if not src.is_dir(): print(f"ERROR: source root missing: {src}"); return 1
    dst.mkdir(parents=True,exist_ok=True)
    files=sorted([p for p in src.rglob("*") if p.is_file() and p.suffix.lower()==".tga"],
                 key=lambda p:str(p.relative_to(src)).lower())
    report=dst.parent/"tga_to_png_conversion_report.csv"
    rows=[]; failures=0
    print(f"Source TGAs: {len(files)}")
    for i,s in enumerate(files,1):
        rel=s.relative_to(src); d=(dst/rel).with_suffix(".png"); d.parent.mkdir(parents=True,exist_ok=True)
        row={"RelativePath":str(rel).replace("/","\\"),"Source":str(s),"Destination":str(d),
             "Width":"","Height":"","TgaImageType":"","BitsPerPixel":"","DecodedPixels":"",
             "RGBA_SHA256":"","PNG_RGBA_SHA256":"","Status":"FAIL","Error":""}
        try:
            image,info=decode_tga(s)
            image.save(d,format="PNG",optimize=False)
            with Image.open(d) as check:
                check.load(); rgba=check.convert("RGBA"); pnghash=hashlib.sha256(rgba.tobytes()).hexdigest()
                if rgba.size!=(info["Width"],info["Height"]): raise ValueError("PNG dimensions differ from decoded TGA")
            if pnghash!=info["RGBA_SHA256"]: raise ValueError("PNG pixels differ from decoded TGA")
            row.update(Width=info["Width"],Height=info["Height"],TgaImageType=info["ImageType"],
                       BitsPerPixel=info["BitsPerPixel"],DecodedPixels=info["DecodedPixels"],
                       RGBA_SHA256=info["RGBA_SHA256"],PNG_RGBA_SHA256=pnghash,Status="PASS")
        except Exception as e:
            failures+=1; row["Error"]=f"{type(e).__name__}: {e}"
        rows.append(row)
        if i%25==0 or i==len(files): print(f"Conversion: {i}/{len(files)}")
    with report.open("w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    passed=len(rows)-failures
    print(f"Converted: {passed}  Failed: {failures}")
    print(f"PNG root: {dst}")
    print(f"Report: {report}")
    if failures:
        for r in rows:
            if r["Status"]!="PASS": print(f"FAIL {r['RelativePath']} :: {r['Error']}")
        return 1
    return 0
if __name__=="__main__": raise SystemExit(main())
