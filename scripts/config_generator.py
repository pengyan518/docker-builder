#!/usr/bin/env python3
"""
config_generator.py - Python 配置生成辅助脚本
用于处理复杂的配置生成、JSON 处理和 API 调用等任务
"""

import json
import os
import sys
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
import subprocess

# 设置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class ConfigGenerator:
    """配置生成器类"""
    
    def __init__(self, work_dir: str, comfyui_dir: str):
        self.work_dir = Path(work_dir)
        self.comfyui_dir = Path(comfyui_dir)
        self.gpu_memory_gb = self._get_gpu_memory()
        
    def _get_gpu_memory(self) -> int:
        """获取 GPU 内存大小"""
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=memory.total', '--format=csv,noheader,nounits'],
                capture_output=True, text=True, check=True
            )
            return int(result.stdout.strip().split('\n')[0]) // 1024  # 转换为 GB
        except (subprocess.CalledProcessError, FileNotFoundError, ValueError):
            logger.warning("无法获取 GPU 内存信息，使用默认值")
            return 8
    
    def generate_supervisor_config(self) -> Dict[str, Any]:
        """生成 Supervisor 配置"""
        config = {
            "unix_http_server": {
                "file": "/tmp/supervisor.sock",
                "chmod": "0700"
            },
            "supervisord": {
                "logfile": f"{self.work_dir}/logs/supervisord.log",
                "logfile_maxbytes": "50MB",
                "logfile_backups": 10,
                "loglevel": "info",
                "pidfile": "/tmp/supervisord.pid",
                "nodaemon": False,
                "minfds": 1024,
                "minprocs": 200
            },
            "rpcinterface:supervisor": {
                "supervisor.rpcinterface_factory": "supervisor.rpcinterface:make_main_rpcinterface"
            },
            "supervisorctl": {
                "serverurl": "unix:///tmp/supervisor.sock"
            },
            "program:comfyui": {
                "command": f"{self.work_dir}/start_comfyui.sh",
                "directory": str(self.comfyui_dir),
                "autostart": True,
                "autorestart": True,
                "stderr_logfile": f"{self.work_dir}/logs/comfyui.error.log",
                "stdout_logfile": f"{self.work_dir}/logs/comfyui.log",
                "environment": f"PATH=\"{self.work_dir}/venv/bin:/usr/local/bin:/usr/bin:/bin\""
            },
            "program:fastapi": {
                "command": f"{self.work_dir}/start_fastapi.sh",
                "directory": str(self.work_dir),
                "autostart": True,
                "autorestart": True,
                "stderr_logfile": f"{self.work_dir}/logs/fastapi.error.log",
                "stdout_logfile": f"{self.work_dir}/logs/fastapi.log",
                "environment": f"PATH=\"{self.work_dir}/venv/bin:/usr/local/bin:/usr/bin:/bin\""
            }
        }
        return config
    
    def generate_nginx_config(self, domain: Optional[str] = None) -> str:
        """生成 Nginx 配置"""
        server_name = domain if domain else "_"
        
        config = f"""
server {{
    listen 80;
    server_name {server_name};
    
    # 静态文件缓存
    location ~* \\.(jpg|jpeg|png|gif|ico|css|js)$ {{
        expires 1y;
        add_header Cache-Control "public, immutable";
    }}
    
    # FastAPI 代理
    location /api/ {{
        proxy_pass http://localhost:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }}
    
    # ComfyUI 代理
    location /comfyui/ {{
        proxy_pass http://localhost:8188/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 大文件上传支持
        client_max_body_size 100M;
        
        # 超时设置
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }}
    
    # WebSocket 直接代理
    location /ws {{
        proxy_pass http://localhost:8188/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 特定设置
        proxy_buffering off;
        proxy_cache off;
    }}
    
    # 默认代理到 FastAPI
    location / {{
        proxy_pass http://localhost:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
}}
"""
        return config.strip()
    
    def generate_comfyui_workflow(self, workflow_type: str = "basic") -> Dict[str, Any]:
        """生成 ComfyUI 工作流配置"""
        workflows = {
            "basic": {
                "1": {
                    "class_type": "CheckpointLoaderSimple",
                    "inputs": {
                        "ckpt_name": "flux1-dev.safetensors"
                    }
                },
                "2": {
                    "class_type": "CLIPTextEncode", 
                    "inputs": {
                        "text": "a beautiful landscape",
                        "clip": ["1", 1]
                    }
                },
                "3": {
                    "class_type": "EmptyLatentImage",
                    "inputs": {
                        "width": 1024,
                        "height": 1024,
                        "batch_size": 1
                    }
                },
                "4": {
                    "class_type": "KSampler",
                    "inputs": {
                        "seed": 42,
                        "steps": 20,
                        "cfg": 7.0,
                        "sampler_name": "euler",
                        "scheduler": "normal",
                        "denoise": 1.0,
                        "model": ["1", 0],
                        "positive": ["2", 0],
                        "negative": ["5", 0],
                        "latent_image": ["3", 0]
                    }
                },
                "5": {
                    "class_type": "CLIPTextEncode",
                    "inputs": {
                        "text": "",
                        "clip": ["1", 1]
                    }
                },
                "6": {
                    "class_type": "VAEDecode",
                    "inputs": {
                        "samples": ["4", 0],
                        "vae": ["1", 2]
                    }
                },
                "7": {
                    "class_type": "SaveImage",
                    "inputs": {
                        "filename_prefix": "ComfyUI",
                        "images": ["6", 0]
                    }
                }
            }
        }
        return workflows.get(workflow_type, workflows["basic"])
    
    def generate_docker_compose(self) -> Dict[str, Any]:
        """生成 Docker Compose 配置"""
        config = {
            "version": "3.8",
            "services": {
                "comfyui-service": {
                    "build": {
                        "context": ".",
                        "dockerfile": "Dockerfile"
                    },
                    "ports": [
                        "8000:8000",
                        "8188:8188"
                    ],
                    "volumes": [
                        f"{self.work_dir}:/app",
                        "/models:/models",
                        "./logs:/app/logs"
                    ],
                    "environment": [
                        "PYTHONPATH=/app",
                        "CUDA_VISIBLE_DEVICES=0"
                    ],
                    "deploy": {
                        "resources": {
                            "reservations": {
                                "devices": [{
                                    "driver": "nvidia",
                                    "count": 1,
                                    "capabilities": ["gpu"]
                                }]
                            }
                        }
                    },
                    "restart": "unless-stopped"
                },
                "nginx": {
                    "image": "nginx:alpine",
                    "ports": ["80:80", "443:443"],
                    "volumes": [
                        "./nginx/nginx.conf:/etc/nginx/nginx.conf",
                        "./nginx/sites-available:/etc/nginx/sites-available",
                        "./nginx/ssl:/etc/nginx/ssl"
                    ],
                    "depends_on": ["comfyui-service"],
                    "restart": "unless-stopped"
                }
            }
        }
        return config
    
    def optimize_for_gpu_memory(self) -> Dict[str, Any]:
        """根据 GPU 内存生成优化配置"""
        if self.gpu_memory_gb >= 24:
            return {
                "memory_management": "high_memory",
                "batch_size": 4,
                "attention_mode": "flash_attention",
                "model_precision": "fp16",
                "cache_models": True,
                "memory_fraction": 0.9
            }
        elif self.gpu_memory_gb >= 12:
            return {
                "memory_management": "medium_memory", 
                "batch_size": 2,
                "attention_mode": "efficient_attention",
                "model_precision": "fp16",
                "cache_models": True,
                "memory_fraction": 0.8
            }
        else:
            return {
                "memory_management": "low_memory",
                "batch_size": 1,
                "attention_mode": "low_mem_attention",
                "model_precision": "fp16",
                "cache_models": False,
                "memory_fraction": 0.7,
                "enable_sequential_cpu_offload": True
            }
    
    def save_config(self, config: Dict[str, Any], filename: str, format_type: str = "json"):
        """保存配置到文件"""
        filepath = self.work_dir / filename
        
        try:
            if format_type == "json":
                with open(filepath, 'w', encoding='utf-8') as f:
                    json.dump(config, f, indent=2, ensure_ascii=False)
            elif format_type == "ini":
                # 简单的 INI 格式写入
                with open(filepath, 'w', encoding='utf-8') as f:
                    for section, values in config.items():
                        f.write(f"[{section}]\n")
                        if isinstance(values, dict):
                            for key, value in values.items():
                                f.write(f"{key} = {value}\n")
                        f.write("\n")
            elif format_type == "text":
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(str(config))
            
            logger.info(f"配置已保存: {filepath}")
            return True
        except Exception as e:
            logger.error(f"保存配置失败: {e}")
            return False

def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="生成配置文件")
    parser.add_argument("--work-dir", default="/my-hybrid-service", help="工作目录")
    parser.add_argument("--comfyui-dir", default="/workspace/ComfyUI", help="ComfyUI目录")
    parser.add_argument("--config-type", required=True, 
                       choices=["supervisor", "nginx", "docker", "workflow", "optimization"],
                       help="配置类型")
    parser.add_argument("--output", help="输出文件名")
    parser.add_argument("--domain", help="域名（仅用于nginx配置）")
    parser.add_argument("--workflow-type", default="basic", help="工作流类型")
    
    args = parser.parse_args()
    
    # 创建配置生成器
    generator = ConfigGenerator(args.work_dir, args.comfyui_dir)
    
    # 根据类型生成配置
    if args.config_type == "supervisor":
        config = generator.generate_supervisor_config()
        output_file = args.output or "supervisord.conf"
        generator.save_config(config, output_file, "ini")
        
    elif args.config_type == "nginx":
        config_text = generator.generate_nginx_config(args.domain)
        output_file = args.output or "nginx_site.conf"
        generator.save_config(config_text, output_file, "text")
        
    elif args.config_type == "docker":
        config = generator.generate_docker_compose()
        output_file = args.output or "docker-compose.yml"
        with open(generator.work_dir / output_file, 'w') as f:
            import yaml
            yaml.dump(config, f, default_flow_style=False)
        logger.info(f"Docker Compose配置已保存: {output_file}")
        
    elif args.config_type == "workflow":
        config = generator.generate_comfyui_workflow(args.workflow_type)
        output_file = args.output or f"workflow_{args.workflow_type}.json"
        generator.save_config(config, output_file, "json")
        
    elif args.config_type == "optimization":
        config = generator.optimize_for_gpu_memory()
        output_file = args.output or "gpu_optimization.json"
        generator.save_config(config, output_file, "json")
    
    print(f"✅ {args.config_type} 配置生成完成")

if __name__ == "__main__":
    main()
