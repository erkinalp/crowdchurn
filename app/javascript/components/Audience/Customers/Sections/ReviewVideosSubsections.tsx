import * as React from "react";

import {
  Review,
  ReviewVideo,
  approveReviewVideo,
  rejectReviewVideo,
} from "$app/data/customers";

import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Modal } from "$app/components/Modal";
import { ReviewVideoPlayer } from "$app/components/ReviewVideoPlayer";
import { useClientAlert } from "$app/components/ClientAlertProvider";

type ReviewVideosSubsectionsProps = {
  review: Review;
  onChange: (review: Review) => void;
};

const ReviewVideosSubsections = ({ review, onChange }: ReviewVideosSubsectionsProps) => {
  const [loading, setLoading] = React.useState(false);
  const [approvedVideoRemovalModalOpen, setApprovedVideoRemovalModalOpen] = React.useState(false);
  const { showAlert } = useClientAlert();
  const approvedVideo = review.videos.find((video) => video.approval_status === "approved");
  const pendingVideo = review.videos.find((video) => video.approval_status === "pending_review");

  const approveVideo = async (video: ReviewVideo) => {
    setLoading(true);

    try {
      await approveReviewVideo(video.id);
      onChange({ ...review, videos: [{ ...video, approval_status: "approved" }] });
      showAlert("This video is now live!", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert("Something went wrong", "error");
    } finally {
      setLoading(false);
    }
  };

  const rejectVideo = async (video: ReviewVideo) => {
    setLoading(true);
    try {
      await rejectReviewVideo(video.id);
      const otherVideos = review.videos.filter((v) => v.id !== video.id);
      onChange({ ...review, videos: [{ ...video, approval_status: "rejected" }, ...otherVideos] });
      showAlert("This video has been removed.", "success");
      setApprovedVideoRemovalModalOpen(false);
    } catch (e) {
      assertResponseError(e);
      showAlert("Something went wrong", "error");
    } finally {
      setLoading(false);
    }
  };

  const approvedVideoSubsection = approvedVideo ? (
    <section>
      <div className="flex flex-col gap-4">
        <h5>Approved video</h5>
        <ReviewVideoPlayer videoId={approvedVideo.id} thumbnail={approvedVideo.thumbnail_url} />
        <Button onClick={() => setApprovedVideoRemovalModalOpen(true)} disabled={loading}>
          Remove
        </Button>
        <Modal
          open={approvedVideoRemovalModalOpen}
          onClose={() => setApprovedVideoRemovalModalOpen(false)}
          title="Remove approved video?"
          footer={
            <>
              <Button onClick={() => setApprovedVideoRemovalModalOpen(false)} disabled={loading}>
                Cancel
              </Button>
              <Button color="danger" onClick={() => void rejectVideo(approvedVideo)} disabled={loading}>
                Remove video
              </Button>
            </>
          }
        >
          <p>This action cannot be undone. This video will be permanently removed from this review.</p>
        </Modal>
      </div>
    </section>
  ) : null;

  const pendingVideoSubsection = pendingVideo ? (
    <section>
      <div className="flex flex-col gap-4">
        <h5>Pending video</h5>
        <ReviewVideoPlayer videoId={pendingVideo.id} thumbnail={pendingVideo.thumbnail_url} />
        <div className="flex flex-row gap-2">
          {pendingVideo.can_approve ? (
            <Button
              color="primary"
              className="flex-1"
              onClick={() => void approveVideo(pendingVideo)}
              disabled={loading}
            >
              Approve
            </Button>
          ) : null}
          {pendingVideo.can_reject ? (
            <Button color="danger" className="flex-1" onClick={() => void rejectVideo(pendingVideo)} disabled={loading}>
              Reject
            </Button>
          ) : null}
        </div>
      </div>
    </section>
  ) : null;

  return approvedVideoSubsection || pendingVideoSubsection ? (
    <>
      {approvedVideoSubsection}
      {pendingVideoSubsection}
    </>
  ) : null;
};

export default ReviewVideosSubsections;
