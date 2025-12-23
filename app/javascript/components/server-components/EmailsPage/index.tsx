import React from "react";
import { RouterProvider, createBrowserRouter, RouteObject, json } from "react-router-dom";
import { StaticRouterProvider } from "react-router-dom/server";

import { getEditInstallment, getNewInstallment } from "$app/data/installments";
import { assertDefined } from "$app/utils/assert";
import { register, GlobalProps, buildStaticRouter } from "$app/utils/serverComponentUtil";

import { EmailForm } from "$app/components/server-components/EmailsPage/EmailForm";

export const emailTabPath = (tab: "published" | "scheduled" | "drafts" | "subscribers") => `/emails/${tab}`;
export const newEmailPath = "/emails/new";
export const editEmailPath = (id: string) => `/emails/${id}/edit`;

// NOTE: published, scheduled, and drafts routes are now handled by Inertia (see app/javascript/pages/Emails/)
// Only new and edit routes remain on react-router
const routes: RouteObject[] = [
  {
    path: newEmailPath,
    element: <EmailForm />,
    loader: async ({ request }) =>
      json(await getNewInstallment(new URL(request.url).searchParams.get("copy_from")), {
        status: 200,
      }),
  },
  {
    path: editEmailPath(":id"),
    element: <EmailForm />,
    loader: async ({ params }) =>
      json(await getEditInstallment(assertDefined(params.id, "Installment ID is required")), { status: 200 }),
  },
];

const EmailsPage = () => {
  const router = createBrowserRouter(routes);

  return <RouterProvider router={router} />;
};

const EmailsRouter = async (global: GlobalProps) => {
  const { router, context } = await buildStaticRouter(global, routes);
  const component = () => <StaticRouterProvider router={router} context={context} nonce={global.csp_nonce} />;
  component.displayName = "EmailsRouter";
  return component;
};

export default register({ component: EmailsPage, ssrComponent: EmailsRouter, propParser: () => ({}) });
