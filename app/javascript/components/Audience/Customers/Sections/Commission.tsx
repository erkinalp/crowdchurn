import { DirectUpload, Blob } from "@rails/activestorage";
import * as React from "react";

import {
  Commission,
  updateCommission,
  completeCommission,
} from "$app/data/customers";
import FileUtils from "$app/utils/file";
import { asyncVoid } from "$app/utils/promise";
import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Icon } from "$app/components/Icons";
import { useClientAlert } from "$app/components/ClientAlertProvider";

import FileRow from "$app/components/Audience/Customers/Sections/FileRow";

type CommissionSectionProps = {
  commission: Commission;
  onChange: (commission: Commission) => void;
};

const CommissionSection = ({ commission, onChange }: CommissionSectionProps) => {
  const [isLoading, setIsLoading] = React.useState(false);
  const { showAlert } = useClientAlert();

  const handleFileChange = asyncVoid(async (event: React.ChangeEvent<HTMLInputElement>) => {
    if (!event.target.files?.length) return;

    setIsLoading(true);

    try {
      const filesToUpload = Array.from(event.target.files);

      const blobs = await Promise.all(
        filesToUpload.map(
          (file) =>
            new Promise<Blob>((resolve, reject) => {
              new DirectUpload(file, Routes.rails_direct_uploads_path()).create((error, blob) => {
                if (error) reject(error);
                else resolve(blob);
              });
            }),
        ),
      );

      await updateCommission(commission.id, [
        ...commission.files.map(({ id }) => id),
        ...blobs.map(({ signed_id }) => signed_id),
      ]);

      onChange({
        ...commission,
        files: [
          ...commission.files,
          ...filesToUpload.map((file, index) => ({
            id: blobs[index]?.signed_id ?? "",
            name: FileUtils.getFileNameWithoutExtension(file.name),
            size: file.size,
            extension: FileUtils.getFileExtension(file.name).toUpperCase(),
            key: blobs[index]?.key ?? "",
          })),
        ],
      });

      showAlert("Uploaded successfully!", "success");
    } catch {
      showAlert("Error uploading files. Please try again.", "error");
    } finally {
      setIsLoading(false);
    }
  });

  const handleDelete = async (fileId: string) => {
    try {
      setIsLoading(true);
      await updateCommission(
        commission.id,
        commission.files.filter(({ id }) => id !== fileId).map(({ id }) => id),
      );
      onChange({
        ...commission,
        files: commission.files.filter(({ id }) => id !== fileId),
      });
      showAlert("File deleted successfully!", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    } finally {
      setIsLoading(false);
    }
  };

  const handleCompletion = async () => {
    try {
      setIsLoading(true);
      await completeCommission(commission.id);
      onChange({ ...commission, status: "completed" });
      showAlert("Commission completed!", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <section className="stack">
      <header>
        <h3>Files</h3>
      </header>
      <section>
        <section className="grid gap-2">
          {commission.files.length ? (
            <div role="tree">
              {commission.files.map((file) => (
                <FileRow key={file.id} file={file} onDelete={() => void handleDelete(file.id)} disabled={isLoading} />
              ))}
            </div>
          ) : null}
          <label className="button">
            <input type="file" onChange={handleFileChange} disabled={isLoading} multiple style={{ display: "none" }} />
            <Icon name="paperclip" /> Upload files
          </label>
          {commission.status === "in_progress" ? (
            <Button color="primary" disabled={isLoading} onClick={() => void handleCompletion()}>
              Submit and mark as complete
            </Button>
          ) : null}
        </section>
      </section>
    </section>
  );
};

export default CommissionSection;
