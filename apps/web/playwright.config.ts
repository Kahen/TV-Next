import { defineConfig,devices } from "@playwright/test";

export default defineConfig({
  testDir:"./e2e",fullyParallel:false,workers:1,retries:0,timeout:45000,
  reporter:[["list"],["html",{open:"never"}]],
  use:{baseURL:process.env.TV_NEXT_TEST_WEB_URL||"http://127.0.0.1:3000",trace:"retain-on-failure",screenshot:"only-on-failure"},
  webServer:{command:"python ../../scripts/browser_media_fixture.py",url:"http://127.0.0.1:8765/fixture.mp4",reuseExistingServer:false,timeout:120000},
  projects:[
    {name:"chromium",use:{...devices["Desktop Chrome"]}},
    {name:"firefox",use:{...devices["Desktop Firefox"]}},
    {name:"webkit",use:{...devices["Desktop Safari"]}}
  ]
});
