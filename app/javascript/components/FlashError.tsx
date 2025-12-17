import { usePage } from "@inertiajs/react";
import * as React from "react";

import { type AlertPayload } from "$app/components/server-components/Alert";

type PageProps = {
  flash?: AlertPayload;
};

export const FlashError: React.FC = () => {
  const { flash } = usePage<PageProps>().props;

  if (flash?.status === "warning" && flash?.message) {
    return (
      <div role="alert" className="danger">
        {flash.message}
      </div>
    );
  }

  return null;
}
