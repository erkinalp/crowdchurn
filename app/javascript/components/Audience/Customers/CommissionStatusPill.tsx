import cx from "classnames";
import { Commission } from "$app/data/customers";

type CommissionStatusPillProps = {
  commission: Commission;
};

const CommissionStatusPill = ({ commission }: CommissionStatusPillProps) => (
  <span
    className={cx("pill small", {
      primary: commission.status === "completed",
      danger: commission.status === "cancelled",
    })}
    style={{ width: "fit-content" }}
  >
    {commission.status === "in_progress"
      ? "In progress"
      : commission.status === "completed"
        ? "Completed"
        : "Cancelled"}
  </span>
);

export default CommissionStatusPill;
