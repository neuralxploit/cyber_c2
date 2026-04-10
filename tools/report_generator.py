"""
HTML Report Generator for CatProtoSpider
Compact, organized HTML reports with smaller text
"""

import os
import re
import markdown
from datetime import datetime
from pathlib import Path


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            font-size: 12px;
            line-height: 1.4;
            padding: 12px;
        }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        
        /* Header */
        .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 14px;
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            margin-bottom: 10px;
        }}
        .header h1 {{ color: #ff7b72; font-size: 1.3em; font-weight: 600; }}
        .header .meta {{ color: #8b949e; font-size: 0.8em; text-align: right; }}
        
        /* Stats Grid */
        .stats {{
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 8px;
            margin-bottom: 10px;
        }}
        .stat {{
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 10px;
            text-align: center;
        }}
        .stat .num {{ font-size: 1.6em; font-weight: 700; color: #58a6ff; }}
        .stat.critical .num {{ color: #f85149; }}
        .stat.warning .num {{ color: #d29922; }}
        .stat.success .num {{ color: #3fb950; }}
        .stat .lbl {{ color: #8b949e; font-size: 0.75em; }}
        
        /* OAST Box */
        .oast-box {{
            background: #161b22;
            border: 1px dashed #58a6ff;
            border-radius: 6px;
            padding: 8px 14px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .oast-box .title {{ color: #58a6ff; font-weight: 600; }}
        .oast-box a {{ color: #ff7b72; text-decoration: none; font-family: monospace; font-size: 0.9em; }}
        .oast-box a:hover {{ text-decoration: underline; }}
        
        /* Sections */
        .section {{
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            margin-bottom: 10px;
            overflow: hidden;
        }}
        .section-header {{
            background: #21262d;
            padding: 8px 12px;
            border-bottom: 1px solid #30363d;
        }}
        .section-header h2 {{ color: #c9d1d9; font-size: 0.95em; font-weight: 600; }}
        .section-body {{ padding: 10px 12px; }}
        
        /* Markdown Content - COMPACT */
        .content {{ line-height: 1.5; }}
        .content h1 {{ color: #ff7b72; font-size: 1.15em; margin: 12px 0 8px; font-weight: 600; }}
        .content h2 {{ color: #58a6ff; font-size: 1.0em; margin: 10px 0 6px; border-bottom: 1px solid #30363d; padding-bottom: 4px; }}
        .content h3 {{ color: #d29922; font-size: 0.95em; margin: 8px 0 4px; }}
        .content h4 {{ color: #8b949e; font-size: 0.9em; margin: 6px 0 3px; }}
        .content p {{ margin: 4px 0; }}
        .content ul, .content ol {{ margin: 4px 0 4px 16px; }}
        .content li {{ margin: 2px 0; }}
        .content strong {{ color: #c9d1d9; }}
        .content hr {{ border: none; border-top: 1px solid #30363d; margin: 10px 0; }}
        
        /* Code blocks - COMPACT */
        .content code {{
            background: #0d1117;
            padding: 1px 5px;
            border-radius: 3px;
            font-family: 'SF Mono', Consolas, 'Courier New', monospace;
            font-size: 0.9em;
            color: #7ee787;
        }}
        .content pre {{
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 4px;
            padding: 8px;
            margin: 6px 0;
            font-size: 0.8em;
            max-height: 150px;
            overflow: auto;
        }}
        .content pre code {{ background: none; padding: 0; display: block; white-space: pre-wrap; word-break: break-all; }}
        
        /* Tables - COMPACT */
        .content table {{ width: 100%; border-collapse: collapse; margin: 6px 0; font-size: 0.9em; }}
        .content th, .content td {{ padding: 5px 8px; text-align: left; border: 1px solid #30363d; }}
        .content th {{ background: #21262d; color: #8b949e; font-weight: 600; }}
        .content tr:hover {{ background: rgba(56, 139, 253, 0.1); }}
        
        /* Blockquotes */
        .content blockquote {{
            border-left: 2px solid #30363d;
            padding-left: 10px;
            color: #8b949e;
            margin: 6px 0;
        }}
        
        /* Footer */
        .footer {{
            text-align: center;
            padding: 10px;
            color: #484f58;
            font-size: 0.75em;
        }}
        
        /* Responsive */
        @media (max-width: 768px) {{
            .stats {{ grid-template-columns: repeat(2, 1fr); }}
            .header {{ flex-direction: column; text-align: center; gap: 8px; }}
            .oast-box {{ flex-direction: column; gap: 6px; }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🐱 {title}</h1>
            <div class="meta">
                <div>{timestamp}</div>
                <div>Task: {task_id}</div>
            </div>
        </div>
        
        <div class="stats">
            <div class="stat {vuln_class}">
                <div class="num">{vuln_count}</div>
                <div class="lbl">Vulnerabilities</div>
            </div>
            <div class="stat">
                <div class="num">{targets_count}</div>
                <div class="lbl">Targets</div>
            </div>
            <div class="stat">
                <div class="num">{duration}</div>
                <div class="lbl">Duration (s)</div>
            </div>
            <div class="stat {status_class}">
                <div class="num" style="font-size:1em">{status}</div>
                <div class="lbl">Status</div>
            </div>
        </div>
        
        <div class="oast-box">
            <span class="title">🔬 OAST Callbacks</span>
            <a href="{oast_server}" target="_blank">{oast_server}</a>
        </div>
        
        <div class="section">
            <div class="section-header">
                <h2>📋 Scan Results</h2>
            </div>
            <div class="section-body">
                <div class="content">
                    {content}
                </div>
            </div>
        </div>
        
        <div class="footer">
            🐱 CatProtoSpider • Next.js Prototype Pollution Fuzzer
        </div>
    </div>
</body>
</html>
"""


def markdown_to_html(md_content: str) -> str:
    """Convert markdown to HTML with code highlighting."""
    extensions = ['tables', 'fenced_code', 'nl2br']
    html = markdown.markdown(md_content, extensions=extensions)
    return html


def generate_html_report(
    title: str,
    markdown_content: str,
    task_id: str,
    vuln_count: int = 0,
    targets_count: int = 0,
    duration: float = 0,
    oast_server: str = "",
    status: str = "Complete"
) -> str:
    """
    Generate HTML report from markdown content.
    
    Args:
        title: Report title
        markdown_content: The markdown report content
        task_id: Celery task ID
        vuln_count: Number of vulnerabilities found
        targets_count: Number of targets scanned
        duration: Scan duration in seconds
        oast_server: OAST server URL
        status: Scan status
    
    Returns:
        HTML string
    """
    # Convert markdown to HTML
    html_content = markdown_to_html(markdown_content)
    
    # Determine styling classes
    vuln_class = "critical" if vuln_count > 0 else "success"
    status_class = "success" if status == "Complete" else "warning"
    
    # Generate final HTML
    html = HTML_TEMPLATE.format(
        title=title,
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        vuln_count=vuln_count,
        vuln_class=vuln_class,
        targets_count=targets_count,
        duration=f"{duration:.1f}",
        status=status,
        status_class=status_class,
        content=html_content,
        oast_server=oast_server or "N/A",
        task_id=task_id
    )
    
    return html


def save_report(
    report_html: str,
    task_id: str,
    report_type: str = "catprotospider",
    reports_dir: str = None
) -> str:
    """
    Save HTML report to file.
    
    Args:
        report_html: HTML content to save
        task_id: Task ID for filename
        report_type: Type of report (catprotospider, shodan_hunt)
        reports_dir: Directory to save reports (default: reports/)
    
    Returns:
        Path to saved report
    """
    if reports_dir is None:
        reports_dir = Path(__file__).parent.parent / "reports"
    else:
        reports_dir = Path(reports_dir)
    
    # Create reports directory if it doesn't exist
    reports_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{report_type}_{timestamp}_{task_id[:8]}.html"
    filepath = reports_dir / filename
    
    # Write report
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(report_html)
    
    return str(filepath)
