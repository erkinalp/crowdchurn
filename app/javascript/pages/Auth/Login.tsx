import { Link, useForm, usePage } from "@inertiajs/react";
import * as React from "react";

import { ForgotPasswordForm } from "$app/components/Authentication/ForgotPasswordForm";
import { Layout } from "$app/components/Authentication/Layout";
import { SocialAuth } from "$app/components/Authentication/SocialAuth";
import { Button } from "$app/components/Button";
import { PasswordInput } from "$app/components/PasswordInput";
import { Separator } from "$app/components/Separator";
import { useOriginalLocation } from "$app/components/useOriginalLocation";
import { RecaptchaCancelledError, useRecaptcha } from "$app/components/useRecaptcha";
import { type AlertPayload } from "$app/components/server-components/Alert";

type PageProps = {
  auth_props: {
    email: string | null;
    application_name: string | null;
    recaptcha_site_key: string | null;
  };
  flash: AlertPayload;
  title: string;
};

function Login() {
  const { auth_props, flash } = usePage<PageProps>().props;
  const { email: initialEmail, application_name, recaptcha_site_key } = auth_props;

  const url = new URL(useOriginalLocation());
  const next = url.searchParams.get("next");
  const recaptcha = useRecaptcha({ siteKey: recaptcha_site_key });
  const uid = React.useId();
  const [showForgotPassword, setShowForgotPassword] = React.useState(false);

  const form = useForm({
    user: {
      login_identifier: initialEmail ?? "",
      password: "",
    },
    next,
    "g-recaptcha-response": null as string | null,
  });

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    try {
      const recaptchaResponse = recaptcha_site_key !== null ? await recaptcha.execute() : null;
      form.transform((data) => ({
        ...data,
        "g-recaptcha-response": recaptchaResponse,
      }));
      form.post(Routes.login_path());
    } catch (e) {
      if (e instanceof RecaptchaCancelledError) return;
      throw e;
    }
  };

  const errorMessage = flash?.status === "warning" ? (flash?.message ?? null) : null;

  return (
    <Layout
      header={<h1>{application_name ? `Connect ${application_name} to Gumroad` : "Log in"}</h1>}
      headerActions={<Link href={Routes.signup_path({ next })}>Sign up</Link>}
    >
      {showForgotPassword ? (
        <ForgotPasswordForm onClose={() => setShowForgotPassword(false)} />
      ) : (
        <form onSubmit={(e) => void handleSubmit(e)}>
          <SocialAuth />
          <Separator>
            <span>or</span>
          </Separator>
          <section>
            {errorMessage ? (
              <div role="alert" className="danger">
                {errorMessage}
              </div>
            ) : null}
            <fieldset>
              <legend>
                <label htmlFor={`${uid}-email`}>Email</label>
              </legend>
              <input
                id={`${uid}-email`}
                type="email"
                value={form.data.user.login_identifier}
                onChange={(e) => form.setData("user", { ...form.data.user, login_identifier: e.target.value })}
                required
                tabIndex={1}
                autoComplete="email"
              />
            </fieldset>
            <fieldset>
              <legend>
                <label htmlFor={`${uid}-password`}>Password</label>
                <button type="button" className="font-normal underline" onClick={() => setShowForgotPassword(true)}>
                  Forgot your password?
                </button>
              </legend>
              <PasswordInput
                id={`${uid}-password`}
                value={form.data.user.password}
                onChange={(e) => form.setData("user", { ...form.data.user, password: e.target.value })}
                required
                tabIndex={1}
                autoComplete="current-password"
              />
            </fieldset>
            <Button color="primary" type="submit" disabled={form.processing}>
              {form.processing ? "Logging in..." : "Login"}
            </Button>
          </section>
        </form>
      )}
      {recaptcha.container}
    </Layout>
  );
}

Login.disableLayout = true;
export default Login;
