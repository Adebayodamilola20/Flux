import { Composition } from "remotion";
import { Reel, TOTAL } from "./Reel";
export const Root = () => (
  <Composition id="Reel" component={Reel} durationInFrames={TOTAL} fps={30} width={1080} height={1920} />
);
