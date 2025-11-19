import * as React from "react";

import { buttonVariants } from "$app/components/Button";
import { Popover, PopoverContent, PopoverTrigger } from "$app/components/Popover";

type Props = { iosAppUrl: string; androidAppUrl: string };

export const OpenInAppButton = ({ iosAppUrl, androidAppUrl }: Props) => (
  <Popover>
    <PopoverTrigger>
      <div className={buttonVariants()}>Open in app</div>
    </PopoverTrigger>
    <PopoverContent>
      <div className="mx-auto grid w-72 gap-4 text-center">
        <h3>Gumroad Library</h3>
        <div>Download from the App Store</div>
        <div className="grid grid-flow-col justify-between gap-4">
          <a className="button button-apple" href={iosAppUrl} target="_blank" rel="noreferrer">
            App Store
          </a>
          <a className="button button-android" href={androidAppUrl} target="_blank" rel="noreferrer">
            Play Store
          </a>
        </div>
      </div>
    </PopoverContent>
  </Popover>
);
