import { useEffect, useState } from "preact/hooks";

/**
 * A QR code for `url`, drawn as an SVG that fills its box. The library loads only when a code is
 * first shown. `size` sets the box's width (any CSS length); without it, CSS does.
 */
export function QrCode(props: { url: string; label: string; size?: string; class?: string }) {
  const [svg, setSvg] = useState("");
  useEffect(() => {
    let live = true;
    void import("qrcode-generator").then(({ default: qrcode }) => {
      const qr = qrcode(0, "M");
      qr.addData(props.url);
      qr.make();
      if (live) setSvg(qr.createSvgTag({ cellSize: 6, margin: 2, scalable: true }));
    });
    return () => {
      live = false;
    };
  }, [props.url]);
  return (
    <div
      class={`qr ${props.class ?? ""}`}
      role="img"
      aria-label={props.label}
      style={props.size ? { width: props.size } : undefined}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
