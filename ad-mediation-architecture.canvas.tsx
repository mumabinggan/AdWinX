import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Stack,
  Stat,
  Table,
  Text,
  useCanvasState,
  useHostTheme,
} from "cursor/canvas";

type Phase = "test" | "prod";
type Walkthrough = "csj_win" | "bid_win" | "all_bid_fail" | "bid_above_all";

const phases: { id: Phase; label: string }[] = [
  { id: "test", label: "当前：Sigmob 测试期" },
  { id: "prod", label: "之后：Sigmob 竞价上线" },
];

function PhaseToggle({
  phase,
  setPhase,
}: {
  phase: Phase;
  setPhase: (p: Phase) => void;
}) {
  return (
    <Row gap={8} wrap>
      {phases.map((p) => (
        <span key={p.id}>
          <Pill active={phase === p.id} onClick={() => setPhase(p.id)}>
            {p.label}
          </Pill>
        </span>
      ))}
    </Row>
  );
}

function AccentRule({ title, children }: { title: string; children: string }) {
  const theme = useHostTheme();
  return (
    <div
      style={{
        borderLeft: `3px solid ${theme.accent.primary}`,
        paddingLeft: 12,
        minWidth: 0,
      }}
    >
      <Text weight="semibold">{title}</Text>
      <Text tone="secondary" size="small">
        {children}
      </Text>
    </div>
  );
}

function AuctionFlow() {
  const theme = useHostTheme();
  const box = {
    fill: theme.bg.elevated,
    stroke: theme.stroke.secondary,
  };
  const accent = theme.accent.primary;
  const text = theme.text.primary;
  const muted = theme.text.tertiary;
  return (
    <svg
      viewBox="0 0 980 420"
      width="100%"
      role="img"
      aria-label="混合竞价请求时序：并行询价后与瀑布流比价"
    >
      <text x="0" y="18" fill={muted} fontSize="11">
        一次展示请求 · 客户端拍卖引擎
      </text>

      <rect x="0" y="36" width="220" height="56" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="110" y="60" textAnchor="middle" fill={text} fontSize="13" fontWeight="600">
        广告位请求
      </text>
      <text x="110" y="78" textAnchor="middle" fill={muted} fontSize="11">
        拉策略 / 过滤广告源
      </text>

      <line x1="220" y1="64" x2="280" y2="64" stroke={accent} strokeWidth="1.5" />
      <polygon points="280,60 290,64 280,68" fill={accent} />

      <rect x="290" y="36" width="240" height="56" rx="6" fill={box.fill} stroke={accent} />
      <text x="410" y="60" textAnchor="middle" fill={text} fontSize="13" fontWeight="600">
        并行 Bidding
      </text>
      <text x="410" y="78" textAnchor="middle" fill={muted} fontSize="11">
        超时 T_bid · 带 bidFloor
      </text>

      <line x1="530" y1="64" x2="590" y2="64" stroke={accent} strokeWidth="1.5" />
      <polygon points="590,60 600,64 590,68" fill={accent} />

      <rect x="600" y="36" width="180" height="56" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="690" y="60" textAnchor="middle" fill={text} fontSize="13" fontWeight="600">
        P_bid = max(出价)
      </text>
      <text x="690" y="78" textAnchor="middle" fill={muted} fontSize="11">
        无出价则为 0
      </text>

      <line x1="780" y1="64" x2="840" y2="64" stroke={accent} strokeWidth="1.5" />
      <polygon points="840,60 850,64 840,68" fill={accent} />

      <rect x="850" y="36" width="130" height="56" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="915" y="68" textAnchor="middle" fill={text} fontSize="13" fontWeight="600">
        混比
      </text>

      <rect x="0" y="130" width="980" height="1" fill={theme.stroke.tertiary} />

      <text x="0" y="158" fill={muted} fontSize="11">
        瀑布流层（按预设 eCPM 从高到低）只请求 floor ≥ P_bid 的层
      </text>

      <rect x="0" y="176" width="220" height="70" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="110" y="202" textAnchor="middle" fill={text} fontSize="12" fontWeight="600">
        高价层
      </text>
      <text x="110" y="222" textAnchor="middle" fill={muted} fontSize="11">
        填上则与 P_bid 比
      </text>

      <rect x="250" y="176" width="220" height="70" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="360" y="202" textAnchor="middle" fill={text} fontSize="12" fontWeight="600">
        中价层
      </text>
      <text x="360" y="222" textAnchor="middle" fill={muted} fontSize="11">
        高价空填再降
      </text>

      <rect x="500" y="176" width="220" height="70" rx="6" fill={box.fill} stroke={box.stroke} />
      <text x="610" y="202" textAnchor="middle" fill={text} fontSize="12" fontWeight="600">
        低价 / 0 价兜底
      </text>
      <text x="610" y="222" textAnchor="middle" fill={muted} fontSize="11">
        Bidding 全失败才走到这
      </text>

      <rect x="760" y="176" width="220" height="70" rx="6" fill={theme.fill.tertiary} stroke={accent} />
      <text x="870" y="202" textAnchor="middle" fill={text} fontSize="12" fontWeight="600">
        展示赢家
      </text>
      <text x="870" y="222" textAnchor="middle" fill={muted} fontSize="11">
        win/loss 回传竞价源
      </text>

      <line x1="220" y1="211" x2="250" y2="211" stroke={theme.stroke.primary} />
      <line x1="470" y1="211" x2="500" y2="211" stroke={theme.stroke.primary} />
      <line x1="720" y1="211" x2="760" y2="211" stroke={accent} strokeWidth="1.5" />

      <text x="0" y="286" fill={muted} fontSize="11">
        开屏总预算建议 4–5s：Bidding 与穿山甲高价层可并行，不要串完瀑布再询价
      </text>

      <rect x="0" y="304" width="980" height="96" rx="6" fill={theme.fill.quaternary} />
      <text x="16" y="332" fill={text} fontSize="12" fontWeight="600">
        比价规则（统一用分）
      </text>
      <text x="16" y="354" fill={theme.text.secondary} fontSize="12">
        竞价源报价 = SDK 实时出价；瀑布流报价 = 该代码位预设 eCPM（穿山甲/测试期 Sigmob 无实时价）
      </text>
      <text x="16" y="376" fill={theme.text.secondary} fontSize="12">
        同价时优先已填充的 Bidding 广告，减少再 load；穿山甲 0 价层永不参与抢头部
      </text>
    </svg>
  );
}

const walkthroughs: {
  id: Walkthrough;
  label: string;
  setup: string;
  winner: string;
  steps: string[][];
}[] = [
  {
    id: "csj_win",
    label: "穿山甲高价层填上",
    setup: "优量汇 52、百度 48 → P_bid=52。穿山甲层 80 / 40 / 20 / 0。",
    winner: "展示穿山甲 80 元层",
    steps: [
      ["1", "并行询价", "优量汇、百度同时 bid，1.8s 内返回"],
      ["2", "取最高价", "P_bid = 52"],
      ["3", "穿山甲 80", "80 ≥ 52，请求该层，填充成功"],
      ["4", "比价结束", "80 > 52，展示穿山甲；40 / 20 / 0 不再请求"],
      ["5", "然后呢", "优量汇/百度 loss 回传；上报本场拍卖；展示失败才降级"],
    ],
  },
  {
    id: "bid_win",
    label: "高价层空，竞价赢",
    setup: "优量汇 55、百度 40 → P_bid=55。穿山甲 80 层空填。",
    winner: "展示优量汇 55",
    steps: [
      ["1", "并行询价", "优量汇 55、百度 40 已拿到广告"],
      ["2", "取最高价", "P_bid = 55"],
      ["3", "穿山甲 80", "80 ≥ 55，请求；空填或超时"],
      ["4", "穿山甲 40", "40 < 55，跳过（填上也赢不了）"],
      ["5", "然后呢", "展示优量汇；百度 loss；20 / 0 不请求。优量汇 show 失败再走穿山甲剩余层"],
    ],
  },
  {
    id: "all_bid_fail",
    label: "竞价全空",
    setup: "优量汇、百度都无填充。P_bid = 0。",
    winner: "展示穿山甲第一层能填上的广告",
    steps: [
      ["1", "并行询价", "两家超时或无填充"],
      ["2", "取最高价", "P_bid = 0，全部瀑布层都 ≥ 0"],
      ["3", "穿山甲 80→40→20", "从高到低串行，谁先填上用谁"],
      ["4", "仍全空", "请求 0 价兜底层，只保填充"],
      ["5", "然后呢", "无竞价赢家，不用 win/loss；有展示就上报填充来源"],
    ],
  },
  {
    id: "bid_above_all",
    label: "出价高于所有层",
    setup: "优量汇 90、百度 70 → P_bid=90。穿山甲最高层 80。",
    winner: "直接展示优量汇 90",
    steps: [
      ["1", "并行询价", "优量汇 90 已拿到广告"],
      ["2", "取最高价", "P_bid = 90"],
      ["3", "穿山甲四层", "80 / 40 / 20 / 0 全部 < 90，一层都不请求"],
      ["4", "比价结束", "竞价已经赢过整条瀑布"],
      ["5", "然后呢", "展示优量汇；百度 loss。show 失败才回头走穿山甲瀑布"],
    ],
  },
];

function WalkthroughPanel() {
  const [id, setId] = useCanvasState<Walkthrough>("walkthrough", "csj_win");
  const current = walkthroughs.find((w) => w.id === id) ?? walkthroughs[0];
  return (
    <Stack gap={12}>
      <H3>用数字走一遍（然后呢）</H3>
      <Row gap={8} wrap>
        {walkthroughs.map((w) => (
          <span key={w.id}>
            <Pill active={id === w.id} onClick={() => setId(w.id)}>
              {w.label}
            </Pill>
          </span>
        ))}
      </Row>
      <Text tone="secondary" size="small">
        {current.setup} 结果：{current.winner}
      </Text>
      <Table
        headers={["步", "动作", "发生什么"]}
        rows={current.steps}
        striped
      />
    </Stack>
  );
}

export default function AdMediationArchitecture() {
  const [phase, setPhase] = useCanvasState<Phase>("phase", "test");
  const isTest = phase === "test";

  const sourceRows = isTest
    ? [
        ["优量汇", "竞价", "竞价池", "实时出价", "必开", "warning"],
        ["百度", "竞价 + 预设 eCPM", "默认竞价", "实时出价", "竞价为主", "success"],
        ["Sigmob", "竞价 + 预设（测试仅预设）", "瀑布流多层", "预设 eCPM", "当穿山甲同类源", "warning"],
        ["穿山甲", "仅预设 eCPM", "瀑布流 3–5 层", "预设 eCPM", "直连 CSJ，不套 GroMore", "neutral"],
      ]
    : [
        ["优量汇", "竞价", "竞价池", "实时出价", "必开", "warning"],
        ["百度", "竞价 + 预设 eCPM", "默认竞价", "实时出价", "可留 1 个兜底位", "success"],
        ["Sigmob", "竞价 + 预设 eCPM", "切到竞价池", "实时出价", "原瀑布层下线或作兜底", "success"],
        ["穿山甲", "仅预设 eCPM", "瀑布流 3–5 层", "预设 eCPM", "仍不进竞价池", "neutral"],
      ];

  const configRows = isTest
    ? [
        ["ylh_bid", "优量汇", "bidding", "—", "1800ms"],
        ["baidu_bid", "百度", "bidding", "—", "1800ms"],
        ["sigmob_80", "Sigmob", "waterfall", "80 元", "2000ms"],
        ["sigmob_40", "Sigmob", "waterfall", "40 元", "2000ms"],
        ["csj_50", "穿山甲", "waterfall", "50 元", "2000ms"],
        ["csj_30", "穿山甲", "waterfall", "30 元", "2000ms"],
        ["csj_0", "穿山甲", "waterfall", "0（兜底）", "2000ms"],
      ]
    : [
        ["ylh_bid", "优量汇", "bidding", "—", "1800ms"],
        ["baidu_bid", "百度", "bidding", "—", "1800ms"],
        ["sigmob_bid", "Sigmob", "bidding", "—", "1800ms"],
        ["csj_80", "穿山甲", "waterfall", "80 元", "2000ms"],
        ["csj_40", "穿山甲", "waterfall", "40 元", "2000ms"],
        ["csj_15", "穿山甲", "waterfall", "15 元", "2000ms"],
        ["csj_0", "穿山甲", "waterfall", "0（兜底）", "2000ms"],
      ];

  return (
    <Stack gap={22} style={{ padding: 24, maxWidth: 1180 }}>
      <Row justify="space-between" align="start" wrap gap={12}>
        <Stack gap={6}>
          <H1>广告聚合 · 混合竞价架构</H1>
          <Text tone="secondary">
            渠道能力不齐时，不要按 ADN 写死四套逻辑。用「能力声明 + 统一拍卖」：竞价源进实时池，预设
            eCPM 源进瀑布流，一次展示里混比。
          </Text>
        </Stack>
        <Pill active>推荐：Hybrid Auction</Pill>
      </Row>

      <Callout tone="info" title="设计原则">
        Adapter 只声明自己会不会竞价、会不会瀑布；当前用哪种由服务端下发。Sigmob
        测试期走瀑布，正式开通竞价后只改配置、不改拍卖引擎。
      </Callout>

      <Row gap={20} wrap>
        <Stat value="4" label="ADN 直连 Adapter" />
        <Stat value="2" label="广告源运行时模式" tone="info" />
        <Stat value="1" label="客户端拍卖引擎" />
        <Stat value={isTest ? "5–7" : "4–6"} label="单广告位源数量（开屏示例）" />
      </Row>

      <PhaseToggle phase={phase} setPhase={setPhase} />

      <H2>一、渠道能力与运行时角色</H2>
      <Text tone="secondary" size="small">
        能力是 ADN 长期支持面；角色是本次策略里实际怎么用。同一家可以能力双模、运行时只开一种，避免同一曝光双边请求。
      </Text>
      <Table
        headers={["ADN", "能力", "当前角色", "参与比价的价格", "接入策略"]}
        rows={sourceRows.map((r) => r.slice(0, 5))}
        rowTone={sourceRows.map((r) => r[5] as "warning" | "success" | "neutral")}
        striped
      />

      <Grid columns={3} gap={18}>
        <AccentRule title="优量汇">
          只进竞价池。必须做 win/loss 回传。bidFloor 用当前最高瀑布层，逼它超过穿山甲高价层。
        </AccentRule>
        <AccentRule title="百度">
          能竞价就默认竞价。不要同一代码位既竞价又瀑布。填充差时另配 1 个低价瀑布位做备份。
        </AccentRule>
        <AccentRule title="穿山甲 / 测试期 Sigmob">
          无实时价。报价 = 后台预设 eCPM。同一样式 3–5 层，最底层 0 价只保填充，不抢头部。
        </AccentRule>
      </Grid>

      <H2>二、一次请求怎么拍</H2>
      <Callout tone="info" title="不是和四层一起比一次">
        竞价源并行询价，取出价最高的 P_bid。穿山甲按 80 / 40 / 20 / 0 从高到低走：只请求
        floor ≥ P_bid 的层；填上就展示该层，空了再降；剩下比不过 P_bid 的层直接跳过，改展示竞价赢家。
      </Callout>
      <AuctionFlow />
      <WalkthroughPanel />

      <H3>超时预算（按样式）</H3>
      <Table
        headers={["样式", "Bidding 超时", "单层瀑布", "整次总预算", "并行策略"]}
        rows={[
          ["开屏", "1.5–2.0s", "1.5–2.0s", "4–5s", "询价与穿山甲最高层并行"],
          ["激励视频", "2.0–2.5s", "2.0–2.5s", "6–8s", "可预加载缓存，展示时直接拍卖缓存"],
          ["插屏", "2.0s", "2.0s", "5–6s", "与激励相同，注意频控"],
          ["信息流", "1.2–1.5s", "1.2s", "3–4s", "层数宜少，优先竞价"],
        ]}
        striped
        columnAlign={["left", "right", "right", "right", "left"]}
      />

      <H2>三、模块怎么切</H2>
      <Grid columns="1.1fr 1fr" gap={16}>
        <Card>
          <CardHeader trailing={<Text size="small" tone="tertiary">服务端</Text>}>
            Mediation Server
          </CardHeader>
          <CardBody>
            <Stack gap={8}>
              <Text size="small">
                广告位、代码位、模式、底价、超时、AB。SDK 启动拉策略，变更走短缓存。
              </Text>
              <Text size="small" tone="secondary">
                核心下发字段：runtimeMode、floorEcpm、bidTimeout、waterfallTimeout、bidFloorPolicy。
              </Text>
              <Text size="small" tone="secondary">
                Sigmob 竞价开关是配置，不是发版。能力探测失败自动回落瀑布。
              </Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader trailing={<Text size="small" tone="tertiary">客户端</Text>}>
            Auction Engine
          </CardHeader>
          <CardBody>
            <Stack gap={8}>
              <Text size="small">
                不认 ADN 名字，只认 bidding / waterfall 两种候选。比价、超时、取消、展示都在这里。
              </Text>
              <Text size="small" tone="secondary">
                内部价格单位统一为分。Adapter 负责把元、分、美元 CPM 转进来。
              </Text>
              <Text size="small" tone="secondary">
                竞价失败或超时 ≠ 整次失败，继续瀑布；全失败才走 0 价兜底。
              </Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      <Grid columns={2} gap={16}>
        <Card>
          <CardHeader>Adapter SPI</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text size="small">capabilities() → bidding / waterfall</Text>
              <Text size="small">load(slot) → 填充或空，无实时价也可</Text>
              <Text size="small">bid(slot, bidFloor) → 价格 + 广告对象</Text>
              <Text size="small">notifyWin / notifyLoss · show · destroy</Text>
              <Divider />
              <Text size="small" tone="secondary">
                穿山甲 Adapter 只实现 load；优量汇只实现 bid；百度/Sigmob 两个都实现，由
                runtimeMode 决定调哪个。
              </Text>
            </Stack>
          </CardBody>
        </Card>
        <Card>
          <CardHeader>Telemetry</CardHeader>
          <CardBody>
            <Stack gap={6}>
              <Text size="small">一次请求一条拍卖日志：候选、报价、赢家、原因、耗时</Text>
              <Text size="small">分 ADN 看填充、展示、超时、无填充码</Text>
              <Text size="small">结算 eCPM 仍以各家后台/账单为准</Text>
              <Divider />
              <Text size="small" tone="secondary">
                穿山甲 SDK 没有 getPrice。聚合侧报价用配置，不要从 mediaExt 里猜。
              </Text>
            </Stack>
          </CardBody>
        </Card>
      </Grid>

      <H2>四、开屏广告位配置示例</H2>
      <Text tone="secondary" size="small">
        {isTest
          ? "测试期：优量汇+百度询价；Sigmob 与穿山甲一起做分层瀑布。bidFloor = max(Sigmob高价, 穿山甲高价)。"
          : "上线后：三家并行询价；穿山甲独自承担瀑布。Sigmob 旧底价层应下线，避免和竞价位抢同一库存。"}
      </Text>
      <Table
        headers={["源 ID", "ADN", "runtimeMode", "预设 eCPM", "超时"]}
        rows={configRows}
        striped
      />

      <H2>五、落地顺序</H2>
      <Table
        headers={["阶段", "做什么", "完成标准"]}
        rows={[
          [
            "P0 骨架",
            "统一 Adapter、拍卖引擎、策略下发、价格转分",
            "优量汇竞价 + 穿山甲多层瀑布能混比并展示",
          ],
          [
            "P1 测试期",
            "接百度竞价、Sigmob 瀑布；开屏超时与并行",
            "Sigmob 当预设源参与排序，填充与超时可控",
          ],
          [
            "P2 开关",
            "Sigmob bidding 代码进 Adapter，配置默认关",
            "打开开关后该源进竞价池，旧瀑布层自动停用",
          ],
          [
            "P3 调优",
            "bidFloor、层数、AB、win/loss、缓存",
            "eCPM 与填充按样式稳定，对账 GAP 可解释",
          ],
        ]}
        rowTone={["info", "warning", "success", "neutral"]}
      />

      <Callout tone="warning" title="三条红线">
        不要为了穿山甲竞价去套 GroMore。同一曝光不要让同一 ADN
        既竞价又瀑布。测试期 Sigmob 不要假装有实时价——没有出价就用预设 eCPM。
      </Callout>
    </Stack>
  );
}
