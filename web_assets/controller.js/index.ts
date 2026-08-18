import { EReaderApi } from './api/ereader_api';
import { Renderer } from './renderer/renderer';

const api: EReaderApi = new Renderer();
window.api = api;

