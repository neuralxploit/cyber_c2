"""
Tenable CVE Scraper - Search and scrape CVE data from Tenable
Also supports NVD and other CVE sources
"""

import os
import re
import json
import logging
import httpx
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from bs4 import BeautifulSoup
from urllib.parse import quote, urlencode

logger = logging.getLogger(__name__)

# Try to import DuckDuckGo for web search fallback
try:
    from duckduckgo_search import DDGS
    HAS_DDGS = True
except ImportError:
    HAS_DDGS = False


class TenableCVEScraper:
    """Scrape CVE data from Tenable's vulnerability database."""
    
    BASE_URL = "https://www.tenable.com/cve/search"
    CVE_DETAIL_URL = "https://www.tenable.com/cve"
    
    def __init__(self):
        self.client = httpx.Client(
            timeout=30,
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.5",
            }
        )
    
    def search_by_date(self, date: str = None, days_back: int = 0) -> List[Dict[str, Any]]:
        """
        Search CVEs by publication date.
        
        Args:
            date: Date in YYYY-MM-DD format (default: today)
            days_back: Number of days to look back (creates a range)
        
        Returns:
            List of CVE dictionaries
        """
        if date is None:
            date = datetime.now().strftime("%Y-%m-%d")
        
        # Calculate date range
        end_date = date
        if days_back > 0:
            start_dt = datetime.strptime(date, "%Y-%m-%d") - timedelta(days=days_back)
            start_date = start_dt.strftime("%Y-%m-%d")
        else:
            start_date = date
        
        # Build Tenable query
        query = f"publication_date:([{start_date} TO {end_date}])"
        
        return self.search(query)
    
    def search_by_keyword(self, keyword: str, days_back: int = 30) -> List[Dict[str, Any]]:
        """
        Search CVEs by keyword (product name, vendor, etc).
        
        Args:
            keyword: Search term (e.g., "apache", "windows", "tenable")
            days_back: Limit to recent CVEs (default 30 days)
        
        Returns:
            List of CVE dictionaries
        """
        end_date = datetime.now().strftime("%Y-%m-%d")
        start_date = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%d")
        
        # Build query with keyword and date filter
        query = f"{keyword} AND publication_date:([{start_date} TO {end_date}])"
        
        return self.search(query)
    
    def search_by_severity(self, severity: str = "critical", days_back: int = 7) -> List[Dict[str, Any]]:
        """
        Search CVEs by severity level.
        
        Args:
            severity: critical, high, medium, low
            days_back: Limit to recent CVEs
        
        Returns:
            List of CVE dictionaries
        """
        end_date = datetime.now().strftime("%Y-%m-%d")
        start_date = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%d")
        
        # Map severity to Tenable's severity field format (not CVSS score ranges)
        severity_map = {
            "critical": "cvss3_severity:Critical",
            "high": "cvss3_severity:High",
            "medium": "cvss3_severity:Medium",
            "low": "cvss3_severity:Low"
        }
        
        severity_filter = severity_map.get(severity.lower(), severity_map["critical"])
        query = f"{severity_filter} AND publication_date:([{start_date} TO {end_date}])"
        
        return self.search(query)
    
    def search(self, query: str, page: int = 1, sort: str = "newest") -> List[Dict[str, Any]]:
        """
        Generic search on Tenable CVE database.
        
        Args:
            query: Tenable search query
            page: Page number
            sort: Sort order (newest, oldest, cvss)
        
        Returns:
            List of CVE dictionaries
        """
        params = {
            "q": query,
            "sort": sort,
            "page": str(page)
        }
        
        url = f"{self.BASE_URL}?{urlencode(params)}"
        logger.info(f"Searching Tenable CVEs: {url}")
        
        try:
            response = self.client.get(url)
            response.raise_for_status()
            
            return self._parse_search_results(response.text, query)
            
        except Exception as e:
            logger.error(f"Tenable search failed: {e}")
            # Fallback to DuckDuckGo
            if HAS_DDGS:
                return self._ddg_fallback(query)
            return []
    
    def _parse_search_results(self, html: str, query: str) -> List[Dict[str, Any]]:
        """Parse Tenable search results HTML."""
        soup = BeautifulSoup(html, 'html.parser')
        cves = []
        
        # Try to extract from __NEXT_DATA__ JSON (Tenable uses Next.js)
        next_data = soup.find('script', id='__NEXT_DATA__')
        if next_data:
            try:
                data = json.loads(next_data.string)
                page_props = data.get('props', {}).get('pageProps', {})
                
                # Check for search results - Tenable returns in 'cves' array
                search_results = page_props.get('cves', []) or page_props.get('searchResults', [])
                
                if search_results:
                    for item in search_results[:30]:  # Limit to 30
                        # Tenable returns data nested in _source with _id as CVE ID
                        cve_id = item.get('_id', '')
                        cve_data = item.get('_source', item)  # Fallback to item itself if no _source
                        
                        if not cve_id and cve_data:
                            cve_id = cve_data.get('public_display') or cve_data.get('doc_id', '')
                        
                        if not cve_id:
                            continue
                        
                        # Build references dict with categories for display
                        refs = {
                            'exploits': [],
                            'advisories': [],
                            'intelligence': [],
                            'blogs': [],
                            'other': []
                        }
                        ref_cats = cve_data.get('reference_categories', {})
                        
                        for ref in ref_cats.get('exploits', []):
                            refs['exploits'].append({
                                "url": ref.get('url'),
                                "name": ref.get('title') or ref.get('source') or "Exploit"
                            })
                        for ref in ref_cats.get('advisories', []):
                            refs['advisories'].append({
                                "url": ref.get('url'),
                                "name": ref.get('title') or ref.get('source') or "Advisory"
                            })
                        for ref in ref_cats.get('intelligence', []):
                            refs['intelligence'].append({
                                "url": ref.get('url'),
                                "name": ref.get('title') or ref.get('source') or "Intel"
                            })
                        for ref in ref_cats.get('blogs', []):
                            refs['blogs'].append({
                                "url": ref.get('url'),
                                "name": ref.get('title') or ref.get('source') or "Blog"
                            })
                        for ref in ref_cats.get('other', []):
                            refs['other'].append({
                                "url": ref.get('url'),
                                "name": ref.get('title') or ref.get('source') or "Reference"
                            })
                        
                        # Determine severity - check multiple fields
                        severity = (cve_data.get('severity') or 
                                   cve_data.get('cvss4_severity') or
                                   cve_data.get('cvss3_severity') or 
                                   cve_data.get('cvss2_severity') or 
                                   cve_data.get('cvssV3Severity') or
                                   cve_data.get('cvssV2Severity') or
                                   'UNKNOWN')
                        
                        cvss3 = cve_data.get('cvss3_base_score')
                        cvss2 = cve_data.get('cvss2_base_score')
                        
                        cves.append({
                            "cve_id": cve_id,
                            "url": f"{self.CVE_DETAIL_URL}/{cve_id}",
                            "description": cve_data.get('description', ''),
                            "cvss": str(cvss3 or cvss2 or ''),
                            "cvss3": cvss3,
                            "cvss2": cvss2,
                            "cvss3_severity": cve_data.get('cvss3_severity'),
                            "severity": severity.upper() if severity else 'UNKNOWN',
                            "publication_date": cve_data.get('publication_date'),
                            "cisa_kev": cve_data.get('cisa_kev_status', False),
                            "references": refs,
                            "source": "tenable"
                        })
                    
                    if cves:
                        logger.info(f"Found {len(cves)} CVEs from Tenable JSON")
                        return cves
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Failed to parse Tenable JSON: {e}")
        
        # Fallback: Look for CVE links in HTML
        cve_entries = soup.find_all('a', href=lambda x: x and '/cve/CVE-' in x)
        
        seen_cves = set()
        for entry in cve_entries:
            cve_id = entry.get_text(strip=True)
            if not cve_id.startswith('CVE-') or cve_id in seen_cves:
                continue
            
            seen_cves.add(cve_id)
            
            # Try to get surrounding context
            parent = entry.find_parent(['div', 'tr', 'li', 'td'])
            description = ""
            cvss = ""
            severity = ""
            
            if parent:
                # Look for description text
                desc_elem = parent.find(['p', 'span', 'td'])
                if desc_elem:
                    description = desc_elem.get_text(strip=True)[:500]
                
                # Look for CVSS score
                text = parent.get_text()
                cvss_match = re.search(r'(\d+\.\d)', text)
                if cvss_match:
                    cvss = cvss_match.group(1)
                
                # Determine severity
                text_lower = text.lower()
                if 'critical' in text_lower:
                    severity = "CRITICAL"
                elif 'high' in text_lower:
                    severity = "HIGH"
                elif 'medium' in text_lower:
                    severity = "MEDIUM"
                elif 'low' in text_lower:
                    severity = "LOW"
                elif cvss:
                    score = float(cvss)
                    if score >= 9.0:
                        severity = "CRITICAL"
                    elif score >= 7.0:
                        severity = "HIGH"
                    elif score >= 4.0:
                        severity = "MEDIUM"
                    else:
                        severity = "LOW"
            
            cves.append({
                "cve_id": cve_id,
                "url": f"{self.CVE_DETAIL_URL}/{cve_id}",
                "description": description or f"CVE entry for {cve_id}",
                "cvss": cvss,
                "severity": severity or "UNKNOWN",
                "source": "tenable"
            })
        
        # If still no results, look for any CVE pattern
        if not cves:
            logger.warning("No CVEs found in HTML, trying regex fallback...")
            cve_pattern = re.compile(r'CVE-\d{4}-\d{4,7}')
            found_cves = list(set(cve_pattern.findall(html)))[:20]
            
            # Fetch details for each CVE found
            for cve_id in found_cves:
                details = self.get_cve_details(cve_id)
                if details and not details.get('error'):
                    cves.append({
                        "cve_id": cve_id,
                        "url": details.get('url', f"{self.CVE_DETAIL_URL}/{cve_id}"),
                        "description": details.get('description', '')[:500],
                        "cvss": str(details.get('cvss3_score') or details.get('cvss2_score') or ''),
                        "severity": details.get('cvss3_severity') or details.get('cvss2_severity') or 'UNKNOWN',
                        "references": details.get('references', []),
                        "source": "tenable"
                    })
        
        logger.info(f"Found {len(cves)} CVEs from Tenable")
        return cves
    
    def get_cve_details(self, cve_id: str) -> Dict[str, Any]:
        """Get detailed information about a specific CVE."""
        url = f"{self.CVE_DETAIL_URL}/{cve_id}"
        
        try:
            response = self.client.get(url)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Try to extract from __NEXT_DATA__ JSON (Tenable uses Next.js)
            next_data = soup.find('script', id='__NEXT_DATA__')
            if next_data:
                import json
                try:
                    data = json.loads(next_data.string)
                    cve_data = data.get('props', {}).get('pageProps', {}).get('cve', {})
                    
                    if cve_data:
                        # Extract references with categories
                        refs = []
                        ref_cats = cve_data.get('reference_categories', {})
                        
                        # Exploits are most important
                        for ref in ref_cats.get('exploits', []):
                            refs.append({"url": ref.get('url'), "type": "exploit"})
                        for ref in ref_cats.get('advisories', []):
                            refs.append({"url": ref.get('url'), "type": "advisory"})
                        for ref in ref_cats.get('other', []):
                            refs.append({"url": ref.get('url'), "type": "other"})
                        
                        return {
                            "cve_id": cve_data.get('doc_id', cve_id),
                            "url": url,
                            "description": cve_data.get('description', ''),
                            "cvss2_score": cve_data.get('cvss2_base_score'),
                            "cvss2_severity": cve_data.get('cvss2_severity'),
                            "cvss2_vector": cve_data.get('cvss2_base_vector'),
                            "cvss3_score": cve_data.get('cvss3_base_score'),
                            "cvss3_severity": cve_data.get('cvss3_severity'),
                            "cvss3_vector": cve_data.get('cvss3_base_vector'),
                            "cvss4_score": cve_data.get('cvss4_base_score'),
                            "cvss4_severity": cve_data.get('cvss4_severity'),
                            "publication_date": cve_data.get('publication_date'),
                            "cisa_kev": cve_data.get('cisa_kev_status', False),
                            "references": refs,
                            "cpe": cve_data.get('cpe', []),
                            "source": "tenable"
                        }
                except json.JSONDecodeError:
                    pass
            
            # Fallback to HTML parsing
            details = {
                "cve_id": cve_id,
                "url": url,
                "source": "tenable"
            }
            
            # Description from meta tag
            desc_meta = soup.find('meta', {'name': 'description'})
            if desc_meta:
                details["description"] = desc_meta.get('content', '')
            
            return details
            
        except Exception as e:
            logger.error(f"Failed to get CVE details: {e}")
            return {"cve_id": cve_id, "error": str(e)}
    
    def _ddg_fallback(self, query: str) -> List[Dict[str, Any]]:
        """Use DuckDuckGo as fallback for CVE search."""
        if not HAS_DDGS:
            return []
        
        logger.info("Using DuckDuckGo fallback for CVE search...")
        
        try:
            ddg = DDGS()
            search_query = f"site:tenable.com/cve {query}"
            results = list(ddg.text(search_query, max_results=20))
            
            cves = []
            import re
            for r in results:
                # Extract CVE ID from URL or title
                cve_match = re.search(r'CVE-\d{4}-\d{4,7}', r.get('href', '') + r.get('title', ''))
                if cve_match:
                    cve_id = cve_match.group(0)
                    cves.append({
                        "cve_id": cve_id,
                        "url": r.get('href', f"https://www.tenable.com/cve/{cve_id}"),
                        "description": r.get('body', '')[:500],
                        "cvss": "",
                        "severity": "UNKNOWN",
                        "source": "duckduckgo"
                    })
            
            return cves
            
        except Exception as e:
            logger.error(f"DuckDuckGo fallback failed: {e}")
            return []


class NVDScraper:
    """Search CVEs from NIST NVD database via API."""
    
    API_URL = "https://services.nvd.nist.gov/rest/json/cves/2.0"
    
    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.getenv("NVD_API_KEY")
        self.client = httpx.Client(timeout=30)
    
    def search(self, keyword: str, days_back: int = 30, limit: int = 20) -> List[Dict[str, Any]]:
        """Search NVD for CVEs by keyword."""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)
        
        params = {
            "keywordSearch": keyword,
            "pubStartDate": start_date.strftime("%Y-%m-%dT00:00:00.000"),
            "pubEndDate": end_date.strftime("%Y-%m-%dT23:59:59.999"),
            "resultsPerPage": limit
        }
        
        headers = {}
        if self.api_key:
            headers["apiKey"] = self.api_key
        
        try:
            response = self.client.get(self.API_URL, params=params, headers=headers)
            response.raise_for_status()
            data = response.json()
            
            cves = []
            for vuln in data.get("vulnerabilities", []):
                cve = vuln.get("cve", {})
                cve_id = cve.get("id", "")
                
                # Get description
                descriptions = cve.get("descriptions", [])
                desc = next((d["value"] for d in descriptions if d.get("lang") == "en"), "")
                
                # Get CVSS
                metrics = cve.get("metrics", {})
                cvss = ""
                severity = "UNKNOWN"
                
                if "cvssMetricV31" in metrics:
                    cvss_data = metrics["cvssMetricV31"][0]["cvssData"]
                    cvss = str(cvss_data.get("baseScore", ""))
                    severity = cvss_data.get("baseSeverity", "UNKNOWN")
                elif "cvssMetricV30" in metrics:
                    cvss_data = metrics["cvssMetricV30"][0]["cvssData"]
                    cvss = str(cvss_data.get("baseScore", ""))
                    severity = cvss_data.get("baseSeverity", "UNKNOWN")
                
                cves.append({
                    "cve_id": cve_id,
                    "url": f"https://nvd.nist.gov/vuln/detail/{cve_id}",
                    "description": desc[:500],
                    "cvss": cvss,
                    "severity": severity,
                    "source": "nvd"
                })
            
            logger.info(f"Found {len(cves)} CVEs from NVD")
            return cves
            
        except Exception as e:
            logger.error(f"NVD search failed: {e}")
            return []


def search_cves(query: str, source: str = "tenable", days_back: int = 7) -> Dict[str, Any]:
    """
    Unified CVE search function.
    
    Args:
        query: Search query (keyword, date, or "today", "critical", etc.)
        source: "tenable", "nvd", or "all"
        days_back: Days to look back
    
    Returns:
        Dict with results and metadata
    """
    results = {
        "query": query,
        "source": source,
        "timestamp": datetime.now().isoformat(),
        "cves": []
    }
    
    # Parse special queries
    query_lower = query.lower().strip()
    
    tenable = TenableCVEScraper()
    nvd = NVDScraper()
    
    if query_lower in ["today", "latest", "new", "recent"]:
        # Today's CVEs
        if source in ["tenable", "all"]:
            results["cves"].extend(tenable.search_by_date(days_back=0))
        if source in ["nvd", "all"]:
            results["cves"].extend(nvd.search("*", days_back=1))
    
    elif query_lower in ["critical", "high", "medium", "low"]:
        # By severity
        if source in ["tenable", "all"]:
            results["cves"].extend(tenable.search_by_severity(query_lower, days_back))
    
    else:
        # Keyword search
        if source in ["tenable", "all"]:
            results["cves"].extend(tenable.search_by_keyword(query, days_back))
        if source in ["nvd", "all"]:
            results["cves"].extend(nvd.search(query, days_back))
    
    # Deduplicate by CVE ID
    seen = set()
    unique_cves = []
    for cve in results["cves"]:
        if cve["cve_id"] not in seen:
            seen.add(cve["cve_id"])
            unique_cves.append(cve)
    
    results["cves"] = unique_cves
    results["total"] = len(unique_cves)
    
    return results


# CLI for testing
if __name__ == "__main__":
    import sys
    
    query = sys.argv[1] if len(sys.argv) > 1 else "today"
    
    print(f"Searching CVEs: {query}")
    results = search_cves(query, source="tenable")
    
    print(f"\nFound {results['total']} CVEs:\n")
    for cve in results["cves"][:10]:
        print(f"  {cve['cve_id']} [{cve.get('severity', 'N/A')}] - {cve.get('description', '')[:80]}...")
        print(f"    URL: {cve['url']}")
        print()
