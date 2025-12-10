import { createCast } from "ts-safe-cast";

import { register } from "$app/utils/serverComponentUtil";

import { Profile } from "$app/components/Profile";

export default register({ component: Profile, propParser: createCast() });
