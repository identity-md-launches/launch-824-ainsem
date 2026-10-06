import { type Hand, utcTime } from "./data";

export async function downloadCard(hand: Hand): Promise<void> {
  await document.fonts.ready;
  const canvas = document.createElement("canvas");
  canvas.width = 1600;
  canvas.height = 1000;
  const ctx = canvas.getContext("2d");
  if (!ctx)
    throw new Error(
      "Your browser could not create the card. Try another browser.",
    );
  ctx.fillStyle = "#0E0D0B";
  ctx.fillRect(0, 0, 1600, 1000);
  ctx.font = "160px Anton";
  ctx.fillStyle = "#3FA37A";
  ctx.fillText("AI", 72, 204);
  const aiWidth = ctx.measureText("AI").width;
  ctx.fillStyle = "#EFE7D6";
  ctx.fillText("NSEM", 72 + aiWidth, 204);
  ctx.font = '24px "JetBrains Mono"';
  ctx.fillStyle = "#8C8573";
  ctx.fillText("A HAND FROM THE SWARM", 75, 265);
  hand.seats.forEach((seat, index) => {
    const col = index < 7 ? index : index - 7;
    const x = 75 + col * 208 + (index < 7 ? 0 : 104);
    const y = index < 7 ? 320 : 578;
    ctx.fillStyle = "#CDBF9F";
    ctx.fillRect(x + 2, y + 2, 150, 200);
    ctx.fillStyle = "#EFE7D6";
    ctx.fillRect(x, y, 150, 200);
    ctx.fillStyle = "#1F3B2E";
    ctx.font = '24px "JetBrains Mono"';
    ctx.fillText(`#${seat.tokenId}`, x + 12, y + 38);
    ctx.font = "56px Anton";
    ctx.fillText("IMD", x + 23, y + 117);
    ctx.font = '19px "JetBrains Mono"';
    ctx.fillText(String(seat.accepted), x + 12, y + 162);
    ctx.font = '13px "JetBrains Mono"';
    ctx.fillText("ACCEPTED", x + 12, y + 184);
  });
  ctx.fillStyle = "#EFE7D6";
  ctx.font = '32px "JetBrains Mono"';
  ctx.fillText(
    `${hand.total.toLocaleString("en-US")} ACCEPTED BETWEEN THEM`,
    75,
    865,
  );
  ctx.fillStyle = "#8C8573";
  ctx.font = '19px "JetBrains Mono"';
  ctx.fillText(`DEALT ${utcTime(hand.dealtAt)}`, 75, 916);
  ctx.fillText("LIVE SWARM SNAPSHOT · explorer.imd.fun", 75, 955);
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(
      (result) =>
        result
          ? resolve(result)
          : reject(new Error("Could not save the card. Try again.")),
      "image/png",
    ),
  );
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `AINSEM-hand-${hand.dealtAt.replace(/[:.]/g, "-")}.png`;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 10000);
}
