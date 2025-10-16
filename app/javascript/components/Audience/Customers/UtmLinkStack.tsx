import React from 'react';
import { Customer } from "$app/data/customers";

type UtmLinkStackProps = {
  link: Customer["utm_link"];
  showHeader: boolean;
};

const UtmLinkStack = ({ link, showHeader }: UtmLinkStackProps) => {
  if (!link) return null;

  return (
    <section className="stack">
      {showHeader ? (
        <>
          <section>
            <h3>UTM link</h3>
          </section>
          <div>
            <small role="status" className="info">
              <span>
                This sale was driven by a{" "}
                <a href={link.utm_url} target="_blank" rel="noreferrer">
                  UTM link
                </a>
                .
              </span>
            </small>
          </div>
        </>
      ) : null}
      <div>
        <h5>Title</h5>
        <a href={Routes.utm_links_dashboard_path({ query: link.title })} target="_blank" rel="noreferrer">
          {link.title}
        </a>
      </div>
      <div>
        <h5>Source</h5>
        {link.source}
      </div>
      <div>
        <h5>Medium</h5>
        {link.medium}
      </div>
      <div>
        <h5>Campaign</h5>
        {link.campaign}
      </div>
      {link.term ? (
        <div>
          <h5>Term</h5>
          {link.term}
        </div>
      ) : null}
      {link.content ? (
        <div>
          <h5>Content</h5>
          {link.content}
        </div>
      ) : null}
    </section>
  );
};

export default UtmLinkStack;
