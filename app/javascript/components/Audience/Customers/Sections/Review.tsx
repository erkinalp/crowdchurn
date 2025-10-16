import * as React from "react";

import { Review } from "$app/data/customers";

import { RatingStars } from "$app/components/RatingStars";
import { ReviewResponseForm } from "$app/components/ReviewResponseForm";

import ReviewVideosSubsections from "$app/components/Audience/Customers/Sections/ReviewVideosSubsections";

type ReviewSectionProps = {
  review: Review;
  purchaseId: string;
  onChange: (review: Review) => void;
};

const ReviewSection = ({
  review,
  purchaseId,
  onChange,
}: ReviewSectionProps) => (
  <section className="stack">
    <h3>Review</h3>
    <section>
      <h5>Rating</h5>
      <div aria-label={`${review.rating} ${review.rating === 1 ? "star" : "stars"}`}>
        <RatingStars rating={review.rating} />
      </div>
    </section>
    {review.message ? (
      <section>
        <h5>Message</h5>
        {review.message}
      </section>
    ) : null}
    <ReviewVideosSubsections review={review} onChange={onChange} />
    {review.response ? (
      <section>
        <h5>Response</h5>
        {review.response.message}
      </section>
    ) : null}
    <ReviewResponseForm
      message={review.response?.message}
      purchaseId={purchaseId}
      onChange={(response) => onChange({ ...review, response })}
    />
  </section>
);

export default ReviewSection;
