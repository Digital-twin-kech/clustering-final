#!/usr/bin/env python3
"""
Convert PRESENTATION_README.md to PDF with embedded images
"""
import markdown
from weasyprint import HTML, CSS
from pathlib import Path
import base64

def convert_markdown_to_pdf(md_file, output_pdf):
    """Convert markdown file to PDF with images"""

    # Read markdown content
    with open(md_file, 'r', encoding='utf-8') as f:
        md_content = f.read()

    # Convert markdown to HTML
    md = markdown.Markdown(extensions=['extra', 'codehilite', 'tables'])
    html_content = md.convert(md_content)

    # Get base directory for resolving image paths
    base_dir = Path(md_file).parent

    # Process image paths - convert relative paths to absolute
    import re
    def replace_img_src(match):
        img_path = match.group(1)
        full_path = base_dir / img_path
        if full_path.exists():
            # Return absolute file path
            return f'<img src="file://{full_path.absolute()}"'
        return match.group(0)

    html_content = re.sub(r'<img src="([^"]+)"', replace_img_src, html_content)

    # Create full HTML document with styling
    html_template = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <style>
            @page {{
                size: A4;
                margin: 2cm;
            }}
            body {{
                font-family: 'Arial', 'Helvetica', sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 100%;
            }}
            h1 {{
                color: #2c3e50;
                border-bottom: 3px solid #3498db;
                padding-bottom: 10px;
                page-break-after: avoid;
            }}
            h2 {{
                color: #34495e;
                border-bottom: 2px solid #95a5a6;
                padding-bottom: 8px;
                margin-top: 30px;
                page-break-after: avoid;
            }}
            h3 {{
                color: #7f8c8d;
                margin-top: 20px;
                page-break-after: avoid;
            }}
            img {{
                max-width: 100%;
                height: auto;
                display: block;
                margin: 20px auto;
                page-break-inside: avoid;
            }}
            code {{
                background-color: #f4f4f4;
                padding: 2px 6px;
                border-radius: 3px;
                font-family: 'Courier New', monospace;
                font-size: 0.9em;
            }}
            pre {{
                background-color: #f4f4f4;
                padding: 15px;
                border-radius: 5px;
                border-left: 4px solid #3498db;
                overflow-x: auto;
                page-break-inside: avoid;
            }}
            pre code {{
                background-color: transparent;
                padding: 0;
            }}
            ul, ol {{
                margin-left: 20px;
            }}
            li {{
                margin-bottom: 8px;
            }}
            blockquote {{
                border-left: 4px solid #3498db;
                padding-left: 20px;
                margin-left: 0;
                color: #555;
                font-style: italic;
            }}
            table {{
                border-collapse: collapse;
                width: 100%;
                margin: 20px 0;
                page-break-inside: avoid;
            }}
            th, td {{
                border: 1px solid #ddd;
                padding: 12px;
                text-align: left;
            }}
            th {{
                background-color: #3498db;
                color: white;
            }}
            tr:nth-child(even) {{
                background-color: #f9f9f9;
            }}
            .page-break {{
                page-break-after: always;
            }}
        </style>
    </head>
    <body>
        {html_content}
    </body>
    </html>
    """

    # Convert HTML to PDF
    print(f"Converting {md_file} to PDF...")
    HTML(string=html_template, base_url=str(base_dir)).write_pdf(output_pdf)
    print(f"✅ PDF created successfully: {output_pdf}")

if __name__ == "__main__":
    md_file = "/home/prodair/Desktop/MORIUS5090/clustering/PRESENTATION_README.md"
    output_pdf = "/home/prodair/Desktop/MORIUS5090/clustering/PRESENTATION_README.pdf"

    convert_markdown_to_pdf(md_file, output_pdf)