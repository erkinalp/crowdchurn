import * as React from "react";

import { File } from "$app/data/customers";
import FileUtils from "$app/utils/file";

import { Button, NavigationButton } from "$app/components/Button";
import { FileKindIcon } from "$app/components/FileRowContent";
import { Icon } from "$app/components/Icons";

type FileRowProps = {
  file: File;
  disabled?: boolean;
  onDelete?: () => void;
};

const FileRow = ({ file, disabled, onDelete }: FileRowProps) => (
  <div role="treeitem">
    <div className="content">
      <FileKindIcon extension={file.extension} />
      <div>
        <h4>{file.name}</h4>
        <ul className="inline">
          <li>{file.extension}</li>
          <li>{FileUtils.getFullFileSizeString(file.size)}</li>
        </ul>
      </div>
    </div>
    <div className="actions">
      {onDelete ? (
        <Button color="danger" onClick={onDelete} disabled={disabled} aria-label="Delete">
          <Icon name="trash2" />
        </Button>
      ) : null}
      <NavigationButton
        href={Routes.s3_utility_cdn_url_for_blob_path({ key: file.key })}
        download
        target="_blank"
        disabled={disabled}
        aria-label="Download"
      >
        <Icon name="download-fill" />
      </NavigationButton>
    </div>
  </div>
);

export default FileRow;
