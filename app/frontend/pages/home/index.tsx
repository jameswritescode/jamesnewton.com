import { Head } from "@inertiajs/react";

import cs from "./index.module.css";

export default function Home() {
  return (
    <>
      <Head title="James Newton" />
      <div className={cs.root}>hello world</div>
    </>
  );
}
