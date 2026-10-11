# Architecture Specification: Track Expenses (`Track_Expenses.cherri`)

## 1. Executive Summary & Purpose

`Track_Expenses.cherri` is an all-in-one expense tracking and immediate analytical reporting Apple Shortcut written in the [Cherri](https://cherrilang.org/) declarative programming language. It serves as both a transaction logger and an on-demand monthly analytics dashboard for personal expense management on iOS and macOS devices.

Unlike decoupled architectures that separate logging from visualization, `Track_Expenses.cherri` couples transaction input, dynamic category expansion, iCloud-based persistence, statistical aggregation, and an ASCII bar-chart dashboard rendered via Apple Shortcuts' Contact vCard subsystem into a single unified execution cycle.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Track_Expenses.cherri                               │
├───────────────────┬──────────────────────────┬──────────────────────────────┤
│ 1. Intake Router  │ 2. Transaction Engine    │ 3. Analytics & vCard Engine  │
│ - ShortcutInput   │ - Allowance Categories   │ - Timeframe Regex Filtering  │
│ - Regex ^\d{1,3}$ │ - Dynamic "Others" Add   │ - Monthly Category Sums      │
│ - External Dict   │ - 1M Bounds Validation   │ - ASCII Proportional Bars    │
│ - Fallback (@out) │ - iCloud JSON Sync       │ - Results.vcf Menu Render    │
└───────────────────┴──────────────────────────┴──────────────────────────────┘
```

---

## 2. System Context & Storage Topology

The shortcut operates directly inside Apple Shortcuts' sandboxed iCloud Drive container (`~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/` or iOS Files `iCloud Drive/Shortcuts/`).

```
iCloud Drive/Shortcuts/
└── Expenses Tracker/                 <-- Root parent directory
    ├── prefs.json                    <-- Global user preferences & currency symbol
    ├── categories.txt                <-- Master list of category names (newline-separated)
    ├── transactions.json             <-- Monolithic dictionary of all logged records
    └── Receipts/                     <-- Attachment folder for receipts (created on setup)
```

### Storage Artefacts

| File | Type | Persistence Pattern | Purpose |
| :--- | :--- | :--- | :--- |
| `prefs.json` | JSON Object | Read-only at runtime | Stores configuration options, notably currency key `c` (e.g. `₱`, `$`, `€`). |
| `categories.txt` | Raw Text | Read / Append | Plaintext list of user categories. Dynamically expanded when user inputs a custom category under "Others". |
| `transactions.json` | JSON Object | Read / Full Rewrite | Primary datastore. Keyed by composite timestamp-category hashes `{timestamp}{category}`. |
| `Receipts/` | Directory | Idempotent Creation | Storage container for transaction receipts and invoice attachments. |

---

## 3. Component Architecture & Subsystems

The shortcut is organized into three major functional subsystems:

```mermaid
flowchart TD
    subgraph IntakeSubsystem["1. Intake & Routing Subsystem"]
        InputCheck["Evaluate ShortcutInput"]
        OutVar["Normalize to @out"]
        RoutingCheck{"Check @out format"}
        ExternalDict["Automated/External Dict Flow"]
        ManualFlow["Manual Interactive Flow (@out == 1)"]
    end

    subgraph StorageSubsystem["2. Storage & Filesystem Subsystem"]
        EnsureDir["Ensure 'Expenses Tracker' & 'Receipts'"]
        LoadPrefs["Load & Parse prefs.json"]
        LoadCats["Load categories.txt"]
        LoadDB["Load & Parse transactions.json"]
        SaveDB["Write transactions.json (Full Overwrite)"]
    end

    subgraph TransactionSubsystem["3. Transaction Processing Subsystem"]
        PickCat["Choose from Allowance List"]
        AddCat["Create & Append Custom Category"]
        PromptAmt["Prompt Amount (Currency Interpolated)"]
        ValidateAmt{"Amount < 1,000,000?"}
        AssembleTx["Assemble Key: {@t_date}{@chosenCat}"]
    end

    subgraph AnalyticsSubsystem["4. Analytics & Visualization Subsystem"]
        ASCIIChart["Initialize ASCII Glyph Dictionary"]
        FilterMonth["Regex Filter Current Month Keys"]
        CalcTotals["Calculate Month & Category Sums"]
        CalcRatio["Compute % of Month Total"]
        GenBars["Map Ratio to ASCII Blocks"]
        RenderVCF["Build Results.vcf & chooseFromList"]
    end

    InputCheck --> OutVar --> RoutingCheck
    RoutingCheck -- "External Payload" --> ExternalDict
    RoutingCheck -- "@out == 1" --> ManualFlow

    ManualFlow --> EnsureDir --> LoadPrefs --> LoadCats --> LoadDB
    LoadDB --> PickCat
    PickCat -- "'Others'" --> AddCat --> PromptAmt
    PickCat -- "Existing" --> PromptAmt

    PromptAmt --> ValidateAmt
    ValidateAmt -- "Valid" --> AssembleTx --> SaveDB
    ValidateAmt -- "Invalid" --> Retry["runSelf(1) & Exit"]

    SaveDB --> AnalyticsSubsystem
    ASCIIChart --> FilterMonth --> CalcTotals --> CalcRatio --> GenBars --> RenderVCF
```

---

## 4. Architectural User Flows

### Flow 1: Initialization & Ingestion Routing

```mermaid
sequenceDiagram
    autonumber
    actor User as User / Calling Shortcut
    participant Engine as Intake Router
    participant FS as iCloud Drive (Expenses Tracker)

    User->>Engine: Trigger Shortcut (ShortcutInput)
    alt ShortcutInput is empty
        Engine->>Engine: Set @out = 1 (Default to Manual Mode)
    else ShortcutInput contains payload
        Engine->>Engine: Set @out = ShortcutInput
    end

    Engine->>FS: createFolder("Expenses Tracker")
    Engine->>FS: createFolder("Receipts", Parent)
    Engine->>FS: getFile("prefs.json")
    Engine->>FS: getFile("categories.txt")
    Engine->>FS: getFile("transactions.json")

    opt categories.txt missing
        Engine-->>User: Alert: "Welcome! Navigate to Settings to add categories..."
    end

    alt @out contains "@?@"
        Engine->>Engine: Route to Settings / Sub-utility Protocol
    else @out matches regex ^\d{1,3}$ (e.g. manual mode or numeric flag)
        Engine->>Engine: Route to Manual Interactive Flow (@out == 1)
    else @out is structured dictionary
        Engine->>Engine: Route to Direct Headless Ingestion Flow
    end
```

### Flow 2: Manual Transaction Logging Flow

```mermaid
sequenceDiagram
    autonumber
    actor User as User
    participant App as Track Expenses Engine
    participant FS as iCloud Filesystem

    App->>App: @t_date = currentDate()
    App-->>User: chooseFromList(["Dining Out", "Snacks", "Transportation", "School Activities", "Others"])
    User->>App: Selects Category

    alt Selection == "Others"
        App-->>User: prompt("Enter new category name:")
        User->>App: Types new category
        App->>App: uppercase(Input)
        App->>FS: appendToFile("categories.txt", newCategory)
        App->>App: @chosenCat = newCategory
    else Standard Selection
        App->>App: @chosenCat = SelectedItem
    end

    App-->>User: prompt("Transaction amount (" + @prefs['c'] + ")", Number)
    User->>App: Enters amount

    alt Amount >= 1,000,000 (Invalid)
        App-->>User: confirm("⚠︎ Invalid Amount, Please Try Again!")
        App->>App: runSelf(1) [Recursive Restart]
        App->>App: stop()
    else Amount < 1,000,000 (Valid)
        App->>App: Construct Key = "{@t_date}{@chosenCat}"
        App->>App: setValue(@dataD, Key, txData)
        App->>FS: saveFile("transactions.json", @dataD, overwrite=true)
        App->>App: Proceed to Monthly Analytics Engine
    end
```

### Flow 3: Inline Monthly Analytics & ASCII vCard Rendering

```mermaid
sequenceDiagram
    autonumber
    participant Engine as Analytics Engine
    participant DB as transactions.json
    participant VCF as Contact vCard Subsystem
    actor User as User

    Note over Engine: Instantiates ASCII glyph table: {"0":"▎","1":"█",..."10":"██████████"}
    Engine->>DB: Reloads transactions.json & categories.txt
    Engine->>Engine: @timeFrame = CurrentDate (yyyy-MM)
    Engine->>Engine: Filter Keys matching (?m)^{@timeFrame}.*

    alt Transactions Count < 1
        Engine-->>User: Alert: "⚠︎ No Transactions found for {@title}"
        Engine->>Engine: stop()
    end

    loop For each key in current month
        Engine->>Engine: Accumulate transaction amounts
    end
    Engine->>Engine: @MonthTotal = Sum(amounts) rounded to 1 decimal

    loop For each category in @cats
        Engine->>Engine: Filter keys matching (?m)^\d+{@category}$
        Engine->>Engine: Sum category transactions -> @CatTotal
        Engine->>Engine: Compute ratio = (@CatTotal * 100) / @MonthTotal
        Engine->>Engine: Map ratio to ASCII blocks via @chart dictionary
        Engine->>Engine: Format line: [Bar] Category: Total (Percentage%)
    end

    Engine->>VCF: Combine loop results into "Results.vcf"
    Engine-->>User: chooseFromList("Results.vcf") (Visual Interactive Dashboard)
```

---

## 5. Detailed Data Schemas

### 5.1 `prefs.json` (Configuration)

```json
{
  "c": "₱",
  "note": false,
  "schemaVersion": 1
}
```

- `c` *(string)*: Currency symbol displayed in amount prompts and summary views (e.g. `₱`, `$`, `PHP`).
- `note` *(boolean)*: Optional flag indicating whether note capture is toggled.
- `schemaVersion` *(number)*: Schema version tracking.

### 5.2 `categories.txt` (Category Registry)

Plain newline-delimited ASCII/UTF-8 string:

```text
Dining Out
Snacks
Transportation
School Activities
Others
```

When custom categories are created during the "Others" prompt, they are converted to uppercase and appended as a new line.

### 5.3 `transactions.json` (Transaction Store)

The datastore is a monolithic dictionary where every transaction is stored under a composite key formed by concatenating the timestamp and category name:

```json
{
  "20261011160530Dining Out": {
    "am": 150.00,
    "stamp": "2026-10-11 16:05:30",
    "usr": "iPhone"
  },
  "20261011171240Transportation": {
    "am": 45.00,
    "stamp": "2026-10-11 17:12:40",
    "usr": "iPhone"
  }
}
```

#### Key Structure: `{timestamp}{category}`
- `timestamp`: Formatted date string (`yyyyMMddHHmmss` or locale string from `currentDate()`).
- `category`: Unmodified category string.

#### Value Fields:
- `am`: Numeric transaction value.
- `stamp`: ISO or localized timestamp of record entry.
- `usr`: Host device name retrieved from `getDeviceDetail("Device Name")`.

### 5.4 `Results.vcf` (ASCII Visual vCard Schema)

Apple Shortcuts lacks native charting controls (such as bar charts or pie graphs). `Track_Expenses.cherri` solves this by synthesizing a virtual contact card (`.vcf`) stream. When presented through `chooseFromList()`, Shortcuts renders each contact record as a formatted interactive card with an icon, title, and subtitle:

```vcard
BEGIN:VCARD
VERSION:3.0
N:;Dining Out;;;
FN:██████ Dining Out: ₱1,250.00 (45.2%)
NOTE:Total spent in category Dining Out
END:VCARD
```

---

## 6. Algorithmic Detail: ASCII Bar Chart Generation

The visual rendering engine maps numerical proportions to horizontal block characters using an in-memory lookup table:

```cherri
Text = "{\"0\":\"▎\",\"1\":\"█\",\"2\":\"██\",\"3\":\"███\",\"4\":\"████\",\"5\":\"█████\",\"6\":\"██████\",\"7\":\"███████\",\"8\":\"████████\",\"9\":\"█████████\",\"10\":\"██████████\"}"
```

### Proportional Mapping Algorithm

1. **Category Percentage Calculation**:
   $$\text{Ratio} = \frac{\text{CatTotal} \times 100}{\text{MonthTotal}}$$
2. **Ceiling & Range Normalization**:
   - `ceil(Ratio, "Ones Place")` produces an integer from $0$ to $100$.
3. **Decile Quantization**:
   - If $\text{Ratio} < 1$: Renders sub-block `▎` (`@chart['0']`).
   - If $\text{Ratio} == 100$: Renders 10 full blocks `██████████` (`@chart['10']`).
   - For values $10 \le \text{Ratio} \le 99$: Uses regular expression `^(\d)\d$` to extract the tens digit ($\text{decile} = \lfloor\text{Ratio} / 10\rfloor$) and indexes `@chart[tensDigit]`.
4. **Rendering**:
   - Concatenates `@bar`, category name, formatted currency sum, and percentage string.

---

## 7. Architectural Evaluation & Tradeoffs

While `Track_Expenses.cherri` achieves a complete logging and dashboard experience within a single shortcut, it presents several key architectural tradeoffs:

### 7.1 Identified Bottlenecks & Limitations

| Architectural Area | Implementation in `Track_Expenses.cherri` | Technical Consequence |
| :--- | :--- | :--- |
| **I/O Scaling** | Reads & writes entire `transactions.json` on every run. | **$O(N)$ file growth degradation**: As history grows to hundreds or thousands of transactions, JSON parsing latency increases exponentially, causing UI freezes on mobile devices. |
| **Error Handling & Recursion** | Calls `runSelf(1)` upon invalid amount entry or missing categories. | **Stack frame accumulation**: Spawns a secondary Shortcut process instance rather than looping in-memory, consuming OS memory and causing visual app flashing. |
| **Single Responsibility Principle** | Logs an expense and immediately calculates full monthly analytics in the same invocation. | **Unavoidable latency for fast logging**: A user logging a ₱50 coffee must wait for full statistical aggregation and vCard rendering before the shortcut terminates. |
| **Concurrency / Idempotency** | Monolithic dictionary overwrite without lock semantics. | **Risk of race conditions**: If triggered in rapid succession or across synchronized devices (Mac + iPhone), simultaneous writes can overwrite recent transactions. |
| **Category Fallbacks** | Hardcoded list (`Dining Out`, `Snacks`, etc.) in Cherri source alongside `categories.txt`. | **State drift**: Discrepancies can emerge between categories stored in `categories.txt` and the hardcoded picker list. |

### 7.2 Architectural Advantages

- **Zero External Dependencies**: Operates 100% offline using standard iCloud Drive storage without requiring databases, third-party companion apps, or web APIs.
- **Rich Visual Feedback without Custom Apps**: Leverages the vCard Contacts protocol to produce rich, readable visual progress bars natively inside the Shortcuts UI.
- **Bi-modal Invocation**: Capable of being invoked manually (via home screen/widget) or programmatically via dictionary input from Siri or webhooks.

---

## 8. Alignment with System Architecture Evolution

In the broader `Expenses Tracker` suite, `Track_Expenses.cherri` represents the **monolithic, feature-complete legacy architecture**. 

To address the $O(N)$ parsing bottleneck and execution latency, the next-generation architecture evolves along two separated paths:

```
                      Legacy Monolith (Track_Expenses.cherri)
                     [Input + Storage + Aggregation + vCard UI]
                                        │
                    ┌───────────────────┴───────────────────┐
                    ▼                                       ▼
     Fast Logger (log-expense.cherri)         Analytics Engine (Monthly Analytics)
     - Append-only (data/yyyy-MM.txt)         - Decoupled on-demand reporting
     - Zero transaction history reads         - Reads historical files only when requested
     - Sub-second execution (< 500ms)         - Rich charts, vCards, and breakdowns
     - In-run loop (no runSelf)               - Scheduled or manual execution
```

1. **Decoupled Fast Entry (`log-expense.cherri`)**:
   - Uses append-only text logs (`Expenses Tracker/data/yyyy-MM.txt`).
   - Does not read or parse transaction history when logging.
   - Replaces `runSelf(1)` with native Cherri `for retry in 50` loops.
   - Eliminates analytics overhead from the logging critical path.

2. **Dedicated Reporting Hub (`Monthly Analytics`)**:
   - Reuses the ASCII bar chart and vCard rendering algorithms pioneered in `Track_Expenses.cherri`.
   - Runs independently as a dedicated analytical reporting tool on a scheduled basis or manual request.
